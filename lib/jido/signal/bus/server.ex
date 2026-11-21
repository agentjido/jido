defmodule Jido.Signal.Bus.Server do
  @moduledoc false

  use GenServer

  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Bus.Store
  alias Jido.Signal.Bus.Store.Memory
  alias Jido.Signal.Bus.Subscriptions
  alias Jido.Error
  alias Jido.Telemetry.Signal, as: Telemetry

  @impl GenServer
  def init({name, opts}) do
    with {:ok, store_module, store_state} <- init_store(opts),
         {:ok, latest_cursor, subscriptions, router} <-
           load_store(%{store_module: store_module, store_state: store_state}) do
      {:ok,
       %{
         name: name,
         jido: Keyword.get(opts, :jido),
         registry: Keyword.get(opts, :registry, Jido.Signal.Registry),
         router: router,
         subscriptions: subscriptions,
         monitors: %{},
         store_module: store_module,
         store_state: store_state,
         store_dirty?: false,
         next_cursor: latest_cursor + 1
       }}
    else
      {:error, {:store_error, callback, reason}} ->
        {:stop, {:store_init_failed, callback, reason}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(request, from, %{store_dirty?: true} = state) do
    with :ok <- Store.settle(state),
         {:ok, latest_cursor, subscriptions, _router} <- load_store(state),
         {:ok, recovered} <- recover_publications(state, latest_cursor) do
      state = %{state | next_cursor: latest_cursor + 1, store_dirty?: false}
      state = Subscriptions.recover(state, subscriptions)
      state = Enum.reduce(recovered, state, &Subscriptions.deliver_published(&2, &1.signal))
      handle_call(request, from, state)
    else
      {:error, reason} ->
        {:reply, {:error, {:store_recovery_failed, reason}}, state}
    end
  end

  def handle_call({:subscribe, path, opts}, _from, state) do
    case Subscriptions.subscribe(state, path, opts) do
      {:ok, id, state} -> {:reply, {:ok, id}, state}
      {:error, reason, state} -> reply_error(reason, state)
    end
  end

  def handle_call({:unsubscribe, subscription_id, opts}, _from, state) do
    case Subscriptions.unsubscribe(state, subscription_id, opts) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_subscription, subscription_id}, _from, state) do
    case Subscriptions.delete(state, subscription_id) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> reply_error(reason, state)
    end
  end

  def handle_call({:publish, signals}, _from, state) do
    started_at = System.monotonic_time()

    case publish(state, signals) do
      {:ok, records, state} ->
        Telemetry.execute(
          [:jido, :signal, :bus, :publish],
          %{count: length(records), duration: System.monotonic_time() - started_at},
          %{
            bus_name: state.name,
            bus_jido: state.jido,
            bus_registry: state.registry
          }
        )

        {:reply, {:ok, records}, state}

      {:error, reason, state} ->
        reply_error(reason, state)
    end
  end

  def handle_call({:replay, path, opts}, _from, state) do
    {:reply, replay(state, path, opts), state}
  end

  def handle_call({:ack, durable_id, cursor}, {caller, _tag}, state) do
    case Subscriptions.acknowledge(state, durable_id, cursor, caller) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason, state} -> reply_error(reason, state)
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, Subscriptions.target_down(state, monitor_ref)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def format_status(%{state: state} = status) when is_map(state) do
    %{status | state: redact_state(state)}
  end

  def format_status(status), do: status

  defp reply_error(reason, state),
    do: {:reply, {:error, reason}, %{state | store_dirty?: Store.recovery_required?(reason)}}

  defp recover_publications(%{next_cursor: next} = state, latest) when latest >= next,
    do: replay(state, "**", after: next - 1, limit: latest - next + 1)

  defp recover_publications(%{next_cursor: next}, latest) when latest == next - 1, do: {:ok, []}
  defp recover_publications(_state, _latest), do: {:error, :invalid_store_cursor}

  defp load_store(state) do
    with {:ok, definitions} <- Store.read(state, :list_subscriptions, []),
         {:ok, latest_cursor} <- Store.read(state, :latest_cursor, []),
         :ok <- validate_latest_cursor(latest_cursor),
         {:ok, subscriptions, router} <- Subscriptions.load(definitions),
         :ok <- Subscriptions.validate_loaded_cursors(subscriptions, latest_cursor) do
      {:ok, latest_cursor, subscriptions, router}
    end
  end

  defp publish(state, signals) do
    with {:ok, stored_records, entries, next_cursor} <-
           RecordedSignal.build(signals, state.next_cursor),
         {:ok, state} <- Store.write(state, :append, [stored_records]) do
      state = %{state | next_cursor: next_cursor}

      state =
        Enum.reduce(entries, state, fn {_stored, signal, _public}, state ->
          Subscriptions.deliver_published(state, signal)
        end)

      {:ok, Enum.map(entries, &elem(&1, 2)), state}
    else
      {:error, {:invalid_signal, index, reason}} ->
        {:error,
         Error.validation_error("Signals must be valid Signal structs", %{
           kind: :input,
           subject: :signals,
           field: :signals,
           index: index,
           reason: reason
         }), state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp replay(state, path, opts) when is_list(opts) do
    after_cursor = Keyword.get(opts, :after, 0)
    limit = Keyword.get(opts, :limit, :infinity)

    with {:ok, path} <- Subscriptions.normalize_path(path),
         :ok <- validate_replay_options(opts, after_cursor, limit),
         {:ok, records} <-
           Store.read(state, :read, [[after_cursor: after_cursor, path: path, limit: limit]]),
         {:ok, public} <- RecordedSignal.decode(records) do
      {:ok, public}
    else
      error -> error
    end
  end

  defp replay(_state, _path, _opts), do: {:error, :invalid_options}

  defp validate_replay_options(opts, after_cursor, limit) do
    unsupported = Enum.find(Keyword.keys(opts), &(&1 not in [:after, :limit]))

    cond do
      unsupported ->
        {:error, {:unsupported_option, unsupported}}

      not (is_integer(after_cursor) and after_cursor >= 0) ->
        {:error, {:invalid_option, :after}}

      limit != :infinity and not (is_integer(limit) and limit > 0) ->
        {:error, {:invalid_option, :limit}}

      true ->
        :ok
    end
  end

  defp init_store(opts) do
    store_module = Keyword.get(opts, :store, Memory)
    store_opts = Keyword.get(opts, :store_opts, [])

    store_opts =
      if store_module == Memory do
        Keyword.put_new(store_opts, :max_records, Keyword.get(opts, :max_log_size, 100_000))
      else
        store_opts
      end

    with {:ok, store_state} <- Store.init_adapter(store_module, store_opts) do
      {:ok, store_module, store_state}
    end
  end

  defp validate_latest_cursor(cursor) when is_integer(cursor) and cursor >= 0, do: :ok
  defp validate_latest_cursor(_cursor), do: {:error, :invalid_store_cursor}

  defp redact_state(state) do
    %{
      name: state.name,
      jido: state.jido,
      registry: state.registry,
      next_cursor: state.next_cursor,
      store_module: state.store_module,
      subscription_count: map_size(state.subscriptions),
      monitor_count: map_size(state.monitors)
    }
  end
end
