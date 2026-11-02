defmodule Jido.Signal.Bus.Subscriptions do
  @moduledoc false

  alias Jido.Signal.Bus.DurableSubscription
  alias Jido.Signal.Bus.Selector
  alias Jido.Signal.Bus.Subscriptions.Subscriber
  alias Jido.Signal.ID
  alias Jido.Signal.Router
  alias Jido.Signal.Router.Index

  @subscription_options [:target, :subscription_id, :durable, :start_from, :selector]

  @doc false
  @spec subscribe(map(), Router.path(), keyword()) ::
          {:ok, String.t(), map()} | {:error, term(), map()}
  def subscribe(state, path, opts) do
    with :ok <- validate_options(opts),
         {:ok, path} <- normalize_path(path),
         {:ok, target} <- validate_target(Keyword.get(opts, :target)),
         {:ok, selector} <- compile_selector(opts),
         {:ok, kind, id} <- subscription_identity(opts) do
      case kind do
        :ephemeral -> add_ephemeral(state, id, path, target, selector)
        :durable -> DurableSubscription.attach(state, id, path, target, opts)
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  @doc false
  @spec unsubscribe(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def unsubscribe(state, subscription_id, []) do
    case Map.get(state.subscriptions, subscription_id) do
      nil -> {:error, :subscription_not_found}
      %Subscriber{durable?: true} = subscriber -> DurableSubscription.detach(state, subscriber)
      %Subscriber{} = subscriber -> {:ok, Subscriber.remove_subscriber(state, subscriber)}
    end
  end

  def unsubscribe(_state, _subscription_id, _opts), do: {:error, :invalid_options}

  @doc false
  @spec delete(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def delete(state, subscription_id) do
    case Map.get(state.subscriptions, subscription_id) do
      nil -> {:error, :subscription_not_found}
      %Subscriber{durable?: true} = subscriber -> DurableSubscription.delete(state, subscriber)
      %Subscriber{} = subscriber -> {:ok, Subscriber.remove_subscriber(state, subscriber)}
    end
  end

  @doc false
  @spec acknowledge(map(), String.t(), term(), pid()) ::
          {:ok, map()} | {:error, term(), map()}
  def acknowledge(state, durable_id, cursor, caller) do
    DurableSubscription.acknowledge(state, durable_id, cursor, caller)
  end

  @doc false
  @spec target_down(map(), reference()) :: map()
  def target_down(state, monitor_ref) do
    case Map.pop(state.monitors, monitor_ref) do
      {nil, _monitors} ->
        state

      {subscription_id, monitors} ->
        state = %{state | monitors: monitors}

        case Map.get(state.subscriptions, subscription_id) do
          nil ->
            state

          %Subscriber{durable?: true} = subscriber ->
            DurableSubscription.target_down(state, subscriber)

          %Subscriber{} = subscriber ->
            Subscriber.remove_subscriber(state, subscriber, false)
        end
    end
  end

  @doc false
  @spec deliver_published(map(), Jido.Signal.t()) :: map()
  def deliver_published(%{subscriptions: subscriptions} = state, _signal)
      when map_size(subscriptions) == 0,
      do: state

  def deliver_published(state, signal) do
    # Publication validates Signals before delivery. An empty target list is
    # a normal observation result and needs no routing error.
    state.router
    |> Index.lookup(signal.type, signal)
    |> Enum.reduce(state, &deliver_to_subscription(&1, signal, &2))
  end

  @doc false
  @spec load(term()) :: {:ok, map(), Router.t()} | {:error, term()}
  defdelegate load(definitions), to: DurableSubscription

  @doc false
  @spec validate_loaded_cursors(map(), non_neg_integer()) :: :ok | {:error, atom()}
  defdelegate validate_loaded_cursors(subscriptions, latest_cursor), to: DurableSubscription

  defp validate_options(opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @subscription_options)) do
      nil ->
        cond do
          Keyword.has_key?(opts, :durable) and Keyword.has_key?(opts, :subscription_id) ->
            {:error, {:conflicting_options, [:durable, :subscription_id]}}

          Keyword.has_key?(opts, :start_from) and not Keyword.has_key?(opts, :durable) ->
            {:error, {:requires_option, :start_from, :durable}}

          Keyword.has_key?(opts, :selector) and Keyword.has_key?(opts, :durable) ->
            {:error, {:conflicting_options, [:selector, :durable]}}

          true ->
            :ok
        end

      option ->
        {:error, {:unsupported_option, option}}
    end
  end

  @doc false
  @spec normalize_path(Router.path()) :: {:ok, String.t()} | {:error, term()}
  def normalize_path(path) do
    case Router.normalize({path, :subscription}) do
      {:ok, [route]} -> {:ok, route.path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_target(target) when is_pid(target) do
    cond do
      node(target) != node() -> {:error, :invalid_target}
      target == self() -> {:error, :target_is_bus}
      Process.alive?(target) -> {:ok, target}
      true -> {:error, :target_not_alive}
    end
  end

  defp validate_target(_target), do: {:error, :invalid_target}

  defp compile_selector(opts) do
    case Keyword.get_values(opts, :selector) do
      [] -> {:ok, nil}
      [selector] -> Selector.compile(selector)
      _repeated -> {:error, {:invalid_selector, ":selector must appear once"}}
    end
  end

  defp subscription_identity(opts) do
    case Keyword.fetch(opts, :durable) do
      {:ok, id} when is_binary(id) and byte_size(id) > 0 ->
        {:ok, :durable, id}

      {:ok, _invalid} ->
        {:error, {:invalid_option, :durable}}

      :error ->
        case Keyword.get_lazy(opts, :subscription_id, &ID.generate!/0) do
          id when is_binary(id) and byte_size(id) > 0 -> {:ok, :ephemeral, id}
          _invalid -> {:error, {:invalid_option, :subscription_id}}
        end
    end
  end

  defp add_ephemeral(state, id, path, target, selector) do
    if Map.has_key?(state.subscriptions, id) do
      {:error, :subscription_already_exists, state}
    else
      {monitor_ref, state} = Subscriber.monitor_target(state, id, target)

      subscriber = %Subscriber{
        id: id,
        path: path,
        durable?: false,
        target: target,
        monitor_ref: monitor_ref,
        cursor: 0,
        in_flight: nil,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      state = Subscriber.insert_subscriber(state, subscriber, selector)
      Subscriber.emit_subscription(:attached, state, subscriber)
      {:ok, id, state}
    end
  end

  defp deliver_to_subscription(subscription_id, signal, state) do
    case Map.fetch!(state.subscriptions, subscription_id) do
      %Subscriber{durable?: true} = subscriber ->
        DurableSubscription.deliver(state, subscriber, signal)

      %Subscriber{target: target} = subscriber ->
        send(target, {:signal, signal})
        Subscriber.emit_delivery(state, subscriber, signal)
        state
    end
  end
end
