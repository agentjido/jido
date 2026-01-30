defmodule Jido.Sensor do
  @moduledoc """
  Defines the behaviour and metadata macro for Sensors in the Jido system.

  A Sensor is a pure behaviour that transforms external events into Signals.
  Sensors are stateless modules that define how to initialize, handle events,
  and emit signals. The runtime execution is handled by a separate SensorServer.

  ## Usage

  To define a new Sensor, use the `Jido.Sensor` behaviour in your module:

      defmodule MySensor do
        use Jido.Sensor,
          name: "my_sensor",
          description: "Monitors a specific metric",
          schema: Zoi.object(%{
            metric: Zoi.string()
          })

        @impl true
        def init(config, _context) do
          {:ok, %{metric: config.metric, last_value: nil}}
        end

        @impl true
        def handle_event({:metric_update, value}, state) do
          signal = Jido.Signal.new!(%{
            source: "my_sensor",
            type: "metric.updated",
            data: %{value: value, previous: state.last_value}
          })
          {:ok, %{state | last_value: value}, [signal]}
        end
      end

  ## Callbacks

  Implementing modules must define:

  - `c:init/2`: Initialize sensor state from config and context
  - `c:handle_event/2`: Process incoming events and emit signals

  Optional callbacks:

  - `c:terminate/2`: Called when the sensor is shutting down (default: `:ok`)

  ## Directives

  Callbacks can return directives to request runtime actions:

  - `{:schedule, interval}` - Schedule next poll after interval ms
  - `{:schedule, interval, payload}` - Schedule with custom payload
  - `{:connect, adapter}` - Connect to an external source
  - `{:connect, adapter, opts}` - Connect with options
  - `{:disconnect, adapter}` - Disconnect from a source
  - `{:subscribe, topic}` - Subscribe to a topic/pattern
  - `{:unsubscribe, topic}` - Unsubscribe from a topic
  - `{:emit, signal}` - Emit a signal immediately
  """

  alias Jido.Sensor.Spec

  @type sensor_directive ::
          {:schedule, pos_integer()}
          | {:schedule, pos_integer(), term()}
          | {:connect, atom()}
          | {:connect, atom(), keyword()}
          | {:disconnect, atom()}
          | {:subscribe, term()}
          | {:unsubscribe, term()}
          | {:emit, Jido.Signal.t()}

  @doc """
  Initialize the sensor state.

  Called when the sensor is started. Receives the validated configuration
  and a context map containing runtime information.

  ## Parameters

  - `config` - Validated configuration map (parsed against the sensor's schema)
  - `context` - Runtime context (e.g., sensor id, parent process info)

  ## Returns

  - `{:ok, state}` - Initial state for the sensor
  - `{:ok, state, directives}` - Initial state with startup directives
  - `{:error, reason}` - Initialization failed
  """
  @callback init(config :: map(), context :: map()) ::
              {:ok, state :: term()}
              | {:ok, state :: term(), directives :: [sensor_directive()]}
              | {:error, reason :: term()}

  @doc """
  Handle an incoming event and produce directives.

  Called when the sensor receives an event from its connected source(s).
  Should return directives describing what actions to take.

  ## Parameters

  - `event` - The incoming event (format depends on the source)
  - `state` - Current sensor state

  ## Returns

  - `{:ok, state}` - Updated state with no directives
  - `{:ok, state, directives}` - Updated state with directives to execute
  - `{:error, reason}` - Event handling failed

  ## Directives

  - `{:emit, signal}` - Emit a signal to the connected agent
  - `{:schedule, interval_ms}` - Schedule a `:tick` event after interval
  - `{:schedule, interval_ms, event}` - Schedule a custom event after interval

  ## Example

      def handle_event(:tick, state) do
        signal = Jido.Signal.new!(%{source: "/sensor/example", type: "example.tick"})
        {:ok, state, [{:emit, signal}, {:schedule, 1000}]}
      end
  """
  @callback handle_event(event :: term(), state :: term()) ::
              {:ok, state :: term()}
              | {:ok, state :: term(), directives :: [sensor_directive()]}
              | {:error, reason :: term()}

  @doc """
  Called when the sensor is shutting down.

  Use this to clean up any resources. The default implementation returns `:ok`.

  ## Parameters

  - `reason` - The shutdown reason
  - `state` - Current sensor state

  ## Returns

  - `:ok` - Shutdown complete
  """
  @callback terminate(reason :: term(), state :: term()) :: :ok

  @sensor_config_schema Zoi.object(
                          %{
                            name:
                              Zoi.string(
                                description:
                                  "The name of the Sensor. Must contain only letters, numbers, and underscores."
                              )
                              |> Zoi.refine({Jido.Util, :validate_name, []}),
                            description:
                              Zoi.string(description: "A description of what the Sensor does.")
                              |> Zoi.optional(),
                            schema:
                              Zoi.any(description: "Zoi schema for config validation.")
                              |> Zoi.optional()
                          },
                          coerce: true
                        )

  @doc false
  @spec config_schema() :: Zoi.schema()
  def config_schema, do: @sensor_config_schema

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Sensor

      alias Jido.Sensor
      alias Jido.Sensor.Spec

      @validated_opts (case Zoi.parse(Sensor.config_schema(), Map.new(unquote(opts))) do
                         {:ok, validated} ->
                           validated

                         {:error, errors} ->
                           message =
                             "Invalid Sensor configuration for #{inspect(__MODULE__)}: #{inspect(errors)}"

                           raise CompileError,
                             description: message,
                             file: __ENV__.file,
                             line: __ENV__.line
                       end)

      @doc "Returns the sensor's name."
      @spec name() :: String.t()
      def name, do: @validated_opts.name

      @doc "Returns the sensor's description."
      @spec description() :: String.t() | nil
      def description, do: @validated_opts[:description]

      @doc "Returns the Zoi schema for sensor configuration."
      @spec schema() :: Zoi.schema() | nil
      def schema, do: @validated_opts[:schema]

      @doc """
      Returns the sensor specification.

      The spec contains all metadata needed to configure and run the sensor.
      """
      @spec spec() :: Spec.t()
      def spec do
        Spec.new!(%{
          module: __MODULE__,
          name: name(),
          description: description(),
          schema: schema()
        })
      end

      @doc """
      Returns metadata for Jido.Discovery integration.

      This function is used by `Jido.Discovery` to index sensors
      for fast lookup and filtering.
      """
      @spec __sensor_metadata__() :: map()
      def __sensor_metadata__ do
        %{
          name: name(),
          description: description(),
          schema: schema()
        }
      end

      @doc false
      @impl Jido.Sensor
      @spec terminate(term(), term()) :: :ok
      def terminate(_reason, _state), do: :ok

      defoverridable terminate: 2, name: 0, description: 0, schema: 0
    end
  end
end
