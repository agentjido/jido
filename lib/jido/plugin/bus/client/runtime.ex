defmodule Jido.Plugin.Bus.Client.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Init
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal

  @default_path "**"
  @default_retry_delay 1_000
  @default_timeout 5_000

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%Init{} = init) do
    with {:ok, config} <- validate_options(init) do
      {:ok,
       %{
         agent_server: init.agent_server,
         bus: nil,
         bus_ref: nil,
         config: config,
         pending: nil,
         reconnect_token: nil,
         retry_timer: nil,
         subscription_id: nil
       }, {:continue, :subscribe}}
    end
  end

  @impl true
  def handle_continue(:subscribe, state) do
    case connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason} -> {:stop, {:bus_subscription_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, %{subscription_id: id} = state) when is_binary(id) do
    {:reply, :ok, state}
  end

  def handle_call(:await_ready, _from, state), do: {:reply, {:error, :not_ready}, state}

  @impl true
  def handle_info({:signal, signal}, state) do
    Server.cast(state.agent_server, signal)
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, bus, _reason},
        %{bus: bus, bus_ref: ref} = state
      ) do
    state =
      state
      |> cancel_record_retry()
      |> Map.merge(%{bus: nil, bus_ref: nil, subscription_id: nil})
      |> schedule_reconnect()

    {:noreply, state}
  end

  def handle_info(
        {:signal, durable_id, %RecordedSignal{} = record},
        %{subscription_id: durable_id, pending: nil} = state
      ) do
    deliver_record(record, state)
  end

  def handle_info({:retry_record, token}, %{pending: %{token: token}} = state) do
    state = %{state | retry_timer: nil}

    case state.pending.stage do
      :deliver -> deliver_record(state.pending.record, %{state | pending: nil})
      :ack -> acknowledge(state.pending.record, %{state | pending: nil})
    end
  end

  def handle_info({:reconnect, token}, %{reconnect_token: token} = state) do
    state = %{state | reconnect_token: nil}

    case connect(state) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason} -> {:noreply, schedule_reconnect(state)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{bus: bus, subscription_id: id})
      when is_pid(bus) and is_binary(id) do
    _ = Bus.unsubscribe(bus, id)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp deliver_record(%RecordedSignal{} = record, state) do
    case call_agent(state.agent_server, record.signal, state.config.timeout) do
      {:ok, _agent} -> acknowledge(record, state)
      {:error, reason} -> retry(record, :deliver, reason, state)
    end
  end

  defp acknowledge(%RecordedSignal{} = record, state) do
    case Bus.ack(state.bus, state.subscription_id, record.cursor) do
      :ok -> {:noreply, %{state | pending: nil}}
      {:error, reason} -> retry(record, :ack, reason, state)
    end
  end

  defp retry(record, stage, _reason, state) do
    token = make_ref()
    timer = Process.send_after(self(), {:retry_record, token}, state.config.retry_delay_ms)
    pending = %{record: record, stage: stage, token: token}
    {:noreply, %{state | pending: pending, retry_timer: timer}}
  end

  defp cancel_record_retry(%{retry_timer: nil} = state), do: %{state | pending: nil}

  defp cancel_record_retry(state) do
    _ = Process.cancel_timer(state.retry_timer)
    %{state | pending: nil, retry_timer: nil}
  end

  defp schedule_reconnect(state) do
    token = make_ref()
    Process.send_after(self(), {:reconnect, token}, state.config.retry_delay_ms)
    %{state | reconnect_token: token}
  end

  defp connect(state) do
    with {:ok, bus} <- Bus.whereis(state.config.bus, state.config.lookup_opts),
         {:ok, subscription_id} <- subscribe(bus, state.config) do
      {:ok, %{state | bus: bus, bus_ref: Process.monitor(bus), subscription_id: subscription_id}}
    end
  end

  defp call_agent(agent_server, signal, timeout) do
    Server.call(agent_server, signal, timeout)
  catch
    :exit, reason -> {:error, {:agent_server_unavailable, reason}}
  end

  defp subscribe(bus, %{path: path, durable: nil}), do: Bus.subscribe(bus, path)

  defp subscribe(bus, config) do
    opts = [durable: config.durable]

    opts =
      if is_nil(config.start_from),
        do: opts,
        else: Keyword.put(opts, :start_from, config.start_from)

    Bus.subscribe(bus, config.path, opts)
  end

  defp validate_options(%Init{} = init) do
    opts = init.options
    scope = if Keyword.has_key?(opts, :jido), do: Keyword.get(opts, :jido), else: init.jido

    config = %{
      bus: Keyword.get(opts, :bus),
      durable: Keyword.get(opts, :durable),
      lookup_opts: if(is_nil(scope), do: [], else: [jido: scope]),
      path: Keyword.get(opts, :path, @default_path),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay),
      start_from: Keyword.get(opts, :start_from),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }

    cond do
      is_nil(config.bus) ->
        {:error, {:missing_bus_option, :bus}}

      not is_binary(config.path) or config.path == "" ->
        {:error, {:invalid_bus_path, config.path}}

      not is_nil(config.durable) and
          (not is_binary(config.durable) or config.durable == "") ->
        {:error, {:invalid_durable_id, config.durable}}

      not is_nil(config.start_from) and is_nil(config.durable) ->
        {:error, {:requires_option, :start_from, :durable}}

      not is_integer(config.retry_delay_ms) or config.retry_delay_ms <= 0 ->
        {:error, {:invalid_retry_delay, config.retry_delay_ms}}

      not is_integer(config.timeout) or config.timeout <= 0 ->
        {:error, {:invalid_timeout, config.timeout}}

      true ->
        {:ok, config}
    end
  end
end
