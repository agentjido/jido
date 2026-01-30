defmodule Jido.Sensor.Runtime do
  @moduledoc """
  GenServer runtime for Jido sensors.

  Runtime wraps sensor modules and manages their lifecycle, similar to how
  AgentServer wraps agent modules. It handles configuration validation,
  event scheduling, and signal delivery.

  ## Architecture

  - Single GenServer per sensor instance
  - Configuration validated via sensor module's `schema()` (Zoi.parse)
  - Timer-based event scheduling via `{:schedule, interval_ms}` directives
  - Signal delivery to agent via pid or `Jido.Signal.Dispatch`

  ## Public API

  - `start_link/1` - Start linked to caller
  - `child_spec/1` - Returns a proper child spec with stable id
  - `event/2` - Inject an external event into the sensor

  ## Options

  - `:sensor` - Sensor module (required)
  - `:config` - Configuration map or keyword list for the sensor
  - `:context` - Context map including `:agent_ref`
  - `:id` - Instance ID (auto-generated if not provided)

  ## Signal Delivery

  When the sensor emits a signal:
  - If `agent_ref` is a pid, uses `send(agent_ref, {:signal, signal})` (for testing)
  - Otherwise uses `Jido.Signal.Dispatch.dispatch/2` with target: agent_ref

  ## Examples

      {:ok, pid} = Jido.Sensor.Runtime.start_link(
        sensor: MySensor,
        config: %{interval: 1000},
        context: %{agent_ref: self()}
      )

      # Inject an external event
      Jido.Sensor.Runtime.event(pid, :custom_event)
  """

  use GenServer

  require Logger

  alias Jido.Signal.Dispatch

  @type server :: pid() | atom() | {:via, module(), term()}

  @doc """
  Starts a Sensor.Runtime linked to the calling process.

  ## Options

  - `:sensor` - Sensor module (required)
  - `:config` - Configuration map or keyword list for the sensor (default: %{})
  - `:context` - Context map including `:agent_ref` (default: %{})
  - `:id` - Instance ID (auto-generated if not provided)

  ## Examples

      {:ok, pid} = Jido.Sensor.Runtime.start_link(
        sensor: MySensor,
        config: %{interval: 5000},
        context: %{agent_ref: agent_pid}
      )
  """
  @spec start_link(keyword() | map()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) or is_map(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Returns a child_spec for supervision.

  Uses the `:id` option if provided, otherwise defaults to the module name.
  """
  @spec child_spec(keyword() | map()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = opts[:id] || __MODULE__

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }
  end

  @doc """
  Injects an external event into the sensor.

  The event will be passed to the sensor's `handle_event/2` callback.

  ## Examples

      :ok = Jido.Sensor.Runtime.event(pid, :my_event)
      :ok = Jido.Sensor.Runtime.event(pid, {:data_received, payload})
  """
  @spec event(server(), term()) :: :ok
  def event(server, event) do
    GenServer.cast(server, {:external_event, event})
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    opts = normalize_opts(opts)

    with {:ok, sensor} <- get_required(opts, :sensor),
         true <- Code.ensure_loaded?(sensor),
         {:ok, config} <- parse_config(sensor, opts[:config] || %{}),
         context = opts[:context] || %{},
         id = opts[:id] || Jido.Util.generate_id(),
         {:ok, state, directives} <- call_sensor_init(sensor, config, context, id) do
      runtime_state = %{
        sensor: sensor,
        config: config,
        context: context,
        id: id,
        sensor_state: state,
        timers: %{}
      }

      runtime_state = apply_directives(directives, runtime_state)

      {:ok, runtime_state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_cast({:external_event, event}, state) do
    handle_sensor_event(event, state)
  end

  @impl GenServer
  def handle_info(:tick, state) do
    handle_sensor_event(:tick, state)
  end

  @impl GenServer
  def handle_info({:scheduled_event, event}, state) do
    handle_sensor_event(event, state)
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("Sensor.Runtime #{state.id} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    if function_exported?(state.sensor, :terminate, 2) do
      state.sensor.terminate(reason, state.sensor_state)
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Private: Initialization
  # ---------------------------------------------------------------------------

  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(opts) when is_list(opts), do: opts

  defp get_required(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, {:missing_required_option, key}}
      value -> {:ok, value}
    end
  end

  defp parse_config(sensor, config) do
    config_map = if is_list(config), do: Map.new(config), else: config

    if function_exported?(sensor, :schema, 0) do
      schema = sensor.schema()
      Zoi.parse(schema, config_map)
    else
      {:ok, config_map}
    end
  end

  defp call_sensor_init(sensor, config, context, id) do
    if function_exported?(sensor, :init, 2) do
      case sensor.init(config, context) do
        {:ok, state} ->
          {:ok, state, []}

        {:ok, state, directives} when is_list(directives) ->
          {:ok, state, directives}

        {:error, reason} ->
          {:error, reason}

        other ->
          {:error, {:invalid_init_return, other}}
      end
    else
      {:ok, %{id: id, config: config, context: context}, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Event Handling
  # ---------------------------------------------------------------------------

  defp handle_sensor_event(event, state) do
    if function_exported?(state.sensor, :handle_event, 2) do
      case state.sensor.handle_event(event, state.sensor_state) do
        {:ok, new_sensor_state} ->
          {:noreply, %{state | sensor_state: new_sensor_state}}

        {:ok, new_sensor_state, directives} when is_list(directives) ->
          new_state = %{state | sensor_state: new_sensor_state}
          new_state = apply_directives(directives, new_state)
          {:noreply, new_state}

        {:error, reason} ->
          Logger.warning("Sensor.Runtime #{state.id} handle_event error: #{inspect(reason)}")

          {:noreply, state}

        other ->
          Logger.warning(
            "Sensor.Runtime #{state.id} handle_event returned invalid result: #{inspect(other)}"
          )

          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private: Directive Processing
  # ---------------------------------------------------------------------------

  defp apply_directives(directives, state) do
    Enum.reduce(directives, state, &apply_directive/2)
  end

  defp apply_directive({:schedule, interval_ms}, state) when is_integer(interval_ms) do
    schedule_event(:tick, interval_ms)
    state
  end

  defp apply_directive({:schedule, interval_ms, event}, state) when is_integer(interval_ms) do
    schedule_event(event, interval_ms)
    state
  end

  defp apply_directive({:emit, signal}, state) do
    deliver_signal(signal, state)
    state
  end

  defp apply_directive(directive, state) do
    Logger.warning("Sensor.Runtime #{state.id} ignoring unknown directive: #{inspect(directive)}")

    state
  end

  defp schedule_event(:tick, interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end

  defp schedule_event(event, interval_ms) do
    Process.send_after(self(), {:scheduled_event, event}, interval_ms)
  end

  # ---------------------------------------------------------------------------
  # Private: Signal Delivery
  # ---------------------------------------------------------------------------

  defp deliver_signal(signal, state) do
    agent_ref = get_in(state, [:context, :agent_ref])

    cond do
      is_pid(agent_ref) ->
        send(agent_ref, {:signal, signal})

      agent_ref != nil ->
        if Code.ensure_loaded?(Dispatch) do
          Dispatch.dispatch(signal, agent_ref)
        else
          Logger.warning("Jido.Signal.Dispatch not available, cannot deliver signal")
        end

      true ->
        Logger.debug("Sensor.Runtime #{state.id} has no agent_ref, signal not delivered")
    end
  end
end
