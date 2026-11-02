defmodule Jido.Signal.Bus.DurableSubscription do
  @moduledoc false

  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Bus.Store
  alias Jido.Signal.Bus.Subscriptions.Subscriber
  alias Jido.Signal.Router
  alias Jido.Signal.Telemetry

  @doc false
  @spec attach(map(), String.t(), String.t(), pid(), keyword()) ::
          {:ok, String.t(), map()} | {:error, term(), map()}
  def attach(state, id, path, target, opts) do
    case Map.get(state.subscriptions, id) do
      nil -> create(state, id, path, target, opts)
      subscriber -> attach_existing(state, subscriber, path, target)
    end
  end

  @doc false
  @spec detach(map(), Subscriber.t()) :: {:ok, map()}
  def detach(state, %Subscriber{target: nil}), do: {:ok, state}

  def detach(state, subscriber) do
    state = Subscriber.demonitor_target(state, subscriber)
    subscriber = %{subscriber | target: nil, monitor_ref: nil, in_flight: nil}
    state = Subscriber.put_subscriber(state, subscriber)
    Subscriber.emit_subscription(:detached, state, subscriber)
    {:ok, state}
  end

  @doc false
  @spec delete(map(), Subscriber.t()) :: {:ok, map()} | {:error, term()}
  def delete(state, subscriber) do
    with {:ok, state} <- Store.write(state, :delete_subscription, [subscriber.id]) do
      {:ok, Subscriber.remove_subscriber(state, subscriber)}
    end
  end

  @doc false
  @spec acknowledge(map(), String.t(), term(), pid()) ::
          {:ok, map()} | {:error, term(), map()}
  def acknowledge(state, durable_id, cursor, caller)
      when is_integer(cursor) and cursor >= 0 do
    case Map.get(state.subscriptions, durable_id) do
      nil ->
        {:error, :subscription_not_found, state}

      %Subscriber{durable?: false} ->
        {:error, :subscription_not_durable, state}

      %Subscriber{target: target} when target != caller ->
        {:error, :not_subscription_owner, state}

      %Subscriber{in_flight: nil} ->
        {:error, :no_record_in_flight, state}

      %Subscriber{in_flight: expected} when expected != cursor ->
        {:error, {:unexpected_cursor, expected}, state}

      %Subscriber{} = subscriber ->
        advance_cursor(state, subscriber, cursor)
    end
  end

  def acknowledge(state, _durable_id, _cursor, _caller),
    do: {:error, :invalid_cursor, state}

  @doc false
  @spec target_down(map(), Subscriber.t()) :: map()
  def target_down(state, subscriber) do
    {:ok, state} = detach(state, subscriber)
    state
  end

  @doc false
  @spec deliver(map(), Subscriber.t(), Jido.Signal.t()) :: map()
  def deliver(state, subscriber, signal) do
    case deliver_next(state, subscriber) do
      {:ok, state} -> state
      {:error, reason, state} -> emit_delivery_error(state, subscriber, signal, reason)
    end
  end

  @doc false
  @spec load(term()) :: {:ok, map(), Router.t()} | {:error, term()}
  def load(definitions) when is_list(definitions) and is_integer(length(definitions)) do
    Enum.reduce_while(definitions, {:ok, %{}, Router.new!()}, fn definition,
                                                                 {:ok, subscriptions, router} ->
      with {:ok, subscriber} <- subscriber_from_definition(definition),
           false <- Map.has_key?(subscriptions, subscriber.id),
           {:ok, router} <- Router.add(router, {subscriber.path, subscriber.id}) do
        {:cont, {:ok, Map.put(subscriptions, subscriber.id, subscriber), router}}
      else
        _invalid -> {:halt, {:error, :invalid_store_subscription}}
      end
    end)
  end

  def load(_definitions), do: {:error, :invalid_store_subscriptions}

  @doc false
  @spec validate_loaded_cursors(map(), non_neg_integer()) :: :ok | {:error, atom()}
  def validate_loaded_cursors(subscriptions, latest_cursor) do
    if Enum.all?(subscriptions, fn {_id, subscriber} -> subscriber.cursor <= latest_cursor end),
      do: :ok,
      else: {:error, :invalid_store_subscription_cursor}
  end

  defp create(state, id, path, target, opts) do
    with {:ok, cursor} <- initial_cursor(state, Keyword.get(opts, :start_from, :current)),
         created_at <- DateTime.utc_now() |> DateTime.to_iso8601(),
         definition <- definition(id, path, cursor, created_at),
         {:ok, state} <- Store.write(state, :put_subscription, [definition]) do
      {monitor_ref, state} = Subscriber.monitor_target(state, id, target)

      subscriber = %Subscriber{
        id: id,
        path: path,
        durable?: true,
        target: target,
        monitor_ref: monitor_ref,
        cursor: cursor,
        in_flight: nil,
        created_at: created_at
      }

      state = Subscriber.insert_subscriber(state, subscriber)
      Subscriber.emit_subscription(:attached, state, subscriber)
      finish_attach(state, subscriber)
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp attach_existing(state, %Subscriber{durable?: false}, _path, _target) do
    {:error, :subscription_already_exists, state}
  end

  defp attach_existing(state, subscriber, path, target) do
    if subscriber.path != path do
      {:error, :durable_subscription_conflict, state}
    else
      {state, subscriber} = drop_dead_target(state, subscriber)

      cond do
        subscriber.target == target ->
          {:ok, subscriber.id, state}

        is_pid(subscriber.target) ->
          {:error, :subscription_in_use, state}

        true ->
          {monitor_ref, state} = Subscriber.monitor_target(state, subscriber.id, target)
          subscriber = %{subscriber | target: target, monitor_ref: monitor_ref, in_flight: nil}
          state = Subscriber.put_subscriber(state, subscriber)
          Subscriber.emit_subscription(:attached, state, subscriber)
          finish_attach(state, subscriber)
      end
    end
  end

  defp finish_attach(state, subscriber) do
    case deliver_next(state, subscriber) do
      {:ok, state} ->
        {:ok, subscriber.id, state}

      {:error, reason, state} ->
        emit_store_delivery_error(state, subscriber, reason)
        {:ok, subscriber.id, state}
    end
  end

  defp drop_dead_target(state, %Subscriber{target: target} = subscriber) when is_pid(target) do
    if Process.alive?(target) do
      {state, subscriber}
    else
      {:ok, state} = detach(state, subscriber)
      {state, Map.fetch!(state.subscriptions, subscriber.id)}
    end
  end

  defp drop_dead_target(state, subscriber), do: {state, subscriber}

  defp initial_cursor(_state, :origin), do: {:ok, 0}
  defp initial_cursor(state, :current), do: {:ok, state.next_cursor - 1}

  defp initial_cursor(state, cursor)
       when is_integer(cursor) and cursor >= 0 and cursor < state.next_cursor,
       do: {:ok, cursor}

  defp initial_cursor(_state, _start_from), do: {:error, {:invalid_option, :start_from}}

  defp deliver_next(state, %Subscriber{target: nil}), do: {:ok, state}

  defp deliver_next(state, %Subscriber{in_flight: cursor}) when is_integer(cursor),
    do: {:ok, state}

  defp deliver_next(state, %Subscriber{} = subscriber) do
    with {:ok, records} <-
           Store.read(state, :read, [
             [after_cursor: subscriber.cursor, path: subscriber.path, limit: 1]
           ]),
         {:ok, record} when not is_nil(record) <- first_record(records),
         {:ok, public} <- RecordedSignal.from_record(record) do
      send(subscriber.target, {:signal, subscriber.id, public})
      subscriber = %{subscriber | in_flight: public.cursor}
      state = Subscriber.put_subscriber(state, subscriber)
      Subscriber.emit_delivery(state, subscriber, public.signal, public.cursor)
      {:ok, state}
    else
      {:ok, nil} -> {:ok, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp first_record(records) when is_list(records) and is_integer(length(records)),
    do: {:ok, List.first(records)}

  defp first_record(_records), do: {:error, :invalid_store_records}

  defp advance_cursor(state, subscriber, cursor) do
    case Store.write(state, :put_subscription, [definition(subscriber, cursor)]) do
      {:ok, state} ->
        subscriber = %{subscriber | cursor: cursor, in_flight: nil}
        state = Subscriber.put_subscriber(state, subscriber)

        Telemetry.execute(
          [:jido, :signal, :bus, :ack],
          %{cursor: cursor},
          %{
            bus_name: state.name,
            bus_jido: state.jido,
            bus_registry: state.registry,
            subscription_id: subscriber.id
          }
        )

        case deliver_next(state, subscriber) do
          {:ok, state} ->
            {:ok, state}

          {:error, reason, state} ->
            emit_store_delivery_error(state, subscriber, reason)
            {:ok, state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp subscriber_from_definition(%{
         "format_version" => 1,
         "id" => id,
         "path" => path,
         "cursor" => cursor,
         "created_at" => created_at
       })
       when is_binary(id) and byte_size(id) > 0 and is_binary(path) and is_integer(cursor) and
              cursor >= 0 and is_binary(created_at) do
    with {:ok, _route} <- Router.normalize({path, :subscription}),
         {:ok, _datetime, _offset} <- DateTime.from_iso8601(created_at) do
      {:ok,
       %Subscriber{
         id: id,
         path: path,
         durable?: true,
         target: nil,
         monitor_ref: nil,
         cursor: cursor,
         in_flight: nil,
         created_at: created_at
       }}
    else
      _invalid -> {:error, :invalid_store_subscription}
    end
  end

  defp subscriber_from_definition(_definition), do: {:error, :unsupported_store_subscription}

  defp definition(%Subscriber{} = subscriber, cursor) do
    definition(subscriber.id, subscriber.path, cursor, subscriber.created_at)
  end

  defp definition(id, path, cursor, created_at) do
    %{
      "format_version" => 1,
      "id" => id,
      "path" => path,
      "cursor" => cursor,
      "created_at" => created_at
    }
  end

  defp emit_delivery_error(state, subscriber, signal, reason) do
    Telemetry.execute(
      [:jido, :signal, :bus, :delivery_error],
      %{system_time: System.system_time()},
      %{
        bus_name: state.name,
        bus_jido: state.jido,
        bus_registry: state.registry,
        subscription_id: subscriber.id,
        signal_id: signal.id,
        signal_type: signal.type,
        reason: reason
      },
      signal
    )

    state
  end

  defp emit_store_delivery_error(state, subscriber, reason) do
    Telemetry.execute(
      [:jido, :signal, :bus, :delivery_error],
      %{system_time: System.system_time()},
      %{
        bus_name: state.name,
        bus_jido: state.jido,
        bus_registry: state.registry,
        subscription_id: subscriber.id,
        reason: reason
      }
    )
  end
end
