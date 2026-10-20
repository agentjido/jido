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
    Process.flag(:trap_exit, true)

    with {:ok, config} <- validate_options(init) do
      {:ok,
       %{
         agent_server: init.agent_server,
         config: config,
         connection: nil,
         pending: nil,
         reconnect_token: nil,
         retry_timer: nil
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
  def handle_call(:await_ready, _from, state) do
    case {Bus.whereis(state.config.bus, state.config.lookup_opts), state.connection} do
      {{:ok, registered}, %{bus: current}} when registered == current ->
        {:reply, :ok, state}

      {{:ok, _replacement}, _connection} ->
        state =
          state
          |> disconnect()
          |> Map.put(:reconnect_token, nil)

        case connect(state) do
          {:ok, connected} -> {:reply, :ok, connected}
          {:error, _reason} -> {:reply, {:error, :not_ready}, schedule_reconnect(state)}
        end

      {{:error, _reason}, _connection} ->
        {:reply, {:error, :not_ready}, state}
    end
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    Server.cast(state.agent_server, signal)
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, bus, _reason},
        %{connection: %{bus: bus, ref: ref}} = state
      ) do
    state =
      state
      |> disconnect()
      |> schedule_reconnect()

    {:noreply, state}
  end

  def handle_info(
        {:signal, durable_id, %RecordedSignal{} = record},
        %{connection: %{id: durable_id}, pending: nil} = state
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

  def handle_info(
        {:delivery_result, token, result},
        %{pending: %{stage: :deliver, token: token, record: record}} = state
      ) do
    state = %{state | pending: nil}

    case result do
      {:ok, _agent, _directives} -> acknowledge(record, state)
      {:error, _reason} -> retry(record, :deliver, state)
    end
  end

  def handle_info(
        {:EXIT, worker, _reason},
        %{pending: %{stage: :deliver, worker: worker, record: record}} = state
      ) do
    {:noreply, next} = retry(record, :deliver, %{state | pending: nil})
    {:noreply, next}
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
  def terminate(_reason, state) do
    state = cancel_record_retry(state)

    case state.connection do
      %{bus: bus, id: id} -> Bus.unsubscribe(bus, id)
      nil -> :ok
    end
  end

  defp deliver_record(%RecordedSignal{} = record, state) do
    owner = self()
    token = make_ref()

    {:ok, worker} =
      Task.start_link(fn ->
        result =
          try do
            call_agent(state.agent_server, record.signal, state.config.timeout)
          rescue
            error -> {:error, {:delivery_failed, error}}
          catch
            kind, reason -> {:error, {:delivery_failed, {kind, reason}}}
          end

        send(owner, {:delivery_result, token, result})
      end)

    pending = %{
      record: record,
      stage: :deliver,
      token: token,
      worker: worker
    }

    {:noreply, %{state | pending: pending}}
  end

  defp acknowledge(%RecordedSignal{} = record, state) do
    case Bus.ack(state.connection.bus, state.connection.id, record.cursor) do
      :ok -> {:noreply, %{state | pending: nil}}
      {:error, _reason} -> retry(record, :ack, state)
    end
  end

  defp retry(record, stage, state) do
    token = make_ref()
    timer = Process.send_after(self(), {:retry_record, token}, state.config.retry_delay_ms)
    pending = %{record: record, stage: stage, token: token}
    {:noreply, %{state | pending: pending, retry_timer: timer}}
  end

  defp cancel_record_retry(state) do
    if state.retry_timer, do: Process.cancel_timer(state.retry_timer)

    case state.pending do
      %{worker: worker} -> Process.exit(worker, :kill)
      _pending -> :ok
    end

    %{state | pending: nil, retry_timer: nil}
  end

  defp disconnect(state) do
    state
    |> cancel_record_retry()
    |> Map.put(:connection, nil)
  end

  defp schedule_reconnect(state) do
    token = make_ref()
    Process.send_after(self(), {:reconnect, token}, state.config.retry_delay_ms)
    %{state | reconnect_token: token}
  end

  defp connect(state) do
    with {:ok, bus} <- Bus.whereis(state.config.bus, state.config.lookup_opts),
         {:ok, subscription_id} <- subscribe(bus, state.config) do
      connection = %{bus: bus, id: subscription_id, ref: Process.monitor(bus)}
      {:ok, %{state | connection: connection}}
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
    scope = Keyword.get(opts, :jido, init.jido)

    config = %{
      bus: Keyword.get(opts, :bus),
      durable: Keyword.get(opts, :durable),
      lookup_opts: if(is_nil(scope), do: [], else: [jido: scope]),
      path: Keyword.get(opts, :path, @default_path),
      retry_delay_ms: Keyword.get(opts, :retry_delay_ms, @default_retry_delay),
      start_from: Keyword.get(opts, :start_from),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }

    with :ok <- validate_bus(config.bus),
         :ok <- validate_path(config.path),
         :ok <- validate_durable(config.durable),
         :ok <- validate_start_from(config.start_from, config.durable),
         :ok <- validate_positive(config.retry_delay_ms, :invalid_retry_delay),
         :ok <- validate_positive(config.timeout, :invalid_timeout) do
      {:ok, config}
    end
  end

  defp validate_bus(nil), do: {:error, {:missing_bus_option, :bus}}
  defp validate_bus(_bus), do: :ok

  defp validate_path(path) when is_binary(path) and path != "", do: :ok
  defp validate_path(path), do: {:error, {:invalid_bus_path, path}}

  defp validate_durable(nil), do: :ok
  defp validate_durable(id) when is_binary(id) and id != "", do: :ok
  defp validate_durable(id), do: {:error, {:invalid_durable_id, id}}

  defp validate_start_from(nil, _durable), do: :ok

  defp validate_start_from(_start_from, nil),
    do: {:error, {:requires_option, :start_from, :durable}}

  defp validate_start_from(_start_from, _durable), do: :ok

  defp validate_positive(value, _error) when is_integer(value) and value > 0, do: :ok
  defp validate_positive(value, error), do: {:error, {error, value}}
end
