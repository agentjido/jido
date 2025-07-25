defmodule Jido.Sensor do
  @moduledoc """
  Defines the behavior and implementation for Sensors in the Jido system.

  A Sensor is a GenServer that emits Signals using a Jido.Bus based on specific events and retains a configurable number of last values.

  ## Usage

  To define a new Sensor, use the `Jido.Sensor` behavior in your module:

      defmodule MySensor do
        use Jido.Sensor,
          name: "my_sensor",
          description: "Monitors a specific metric",
          category: :monitoring,
          tags: [:example, :demo],
          vsn: "1.0.0",
          schema: [
            metric: [type: :string, required: true]
          ]

        @impl true
        def generate_signal(state) do
          # Your sensor logic here
          {:ok, Jido.Signal.new(%{
            source: "\#{state.sensor.name}:\#{state.id}",
            topic: "metric_update",
            payload: %{value: get_metric_value()},
            timestamp: DateTime.utc_now()
          })}
        end
      end

  ## Callbacks

  Implementing modules can override the following callbacks:

  - `c:mount/1`: Called when the sensor is initialized.
  - `c:deliver_signal/1`: Generates a signal based on the current state.
  - `c:on_before_deliver/2`: Called before a signal is delivered.
  - `c:shutdown/1`: Called when the sensor is shutting down.
  """

  alias Jido.Error
  alias Jido.Sensor

  require OK

  use TypedStruct

  typedstruct do
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:category, atom())
    field(:tags, [atom()], default: [])
    field(:vsn, String.t())
    field(:schema, NimbleOptions.t())
  end

  @type options :: [
          id: String.t(),
          bus_name: atom(),
          stream_id: String.t(),
          retain_last: pos_integer()
        ]

  @type sensor_result :: {:ok, Jido.Signal.t()} | {:error, any()}

  @sensor_compiletime_options_schema NimbleOptions.new!(
                                       name: [
                                         type: {:custom, Jido.Util, :validate_name, []},
                                         required: true,
                                         doc:
                                           "The name of the Sensor. Must contain only letters, numbers, and underscores."
                                       ],
                                       description: [
                                         type: :string,
                                         required: false,
                                         doc: "A description of what the Sensor does."
                                       ],
                                       category: [
                                         type: :atom,
                                         required: false,
                                         doc: "The category of the Sensor."
                                       ],
                                       tags: [
                                         type: {:list, :atom},
                                         default: [],
                                         doc: "A list of tags associated with the Sensor."
                                       ],
                                       vsn: [
                                         type: :string,
                                         required: false,
                                         doc: "The version of the Sensor."
                                       ],
                                       schema: [
                                         type: :keyword_list,
                                         default: [],
                                         doc:
                                           "A NimbleOptions schema for validating the Sensor's server configuration."
                                       ]
                                     )

  @callback mount(map()) :: {:ok, map()} | {:error, any()}
  @callback deliver_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  @callback on_before_deliver(Jido.Signal.t(), map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  @callback shutdown(map()) :: {:ok, map()} | {:error, any()}

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@sensor_compiletime_options_schema)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote location: :keep do
      @behaviour Jido.Sensor
      @type t :: Jido.Sensor.t()
      @type sensor_result :: Jido.Sensor.sensor_result()

      use GenServer

      require Logger
      require OK

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          @sensor_server_options_schema NimbleOptions.new!(
                                          [
                                            id: [
                                              type: :string,
                                              doc: "Unique identifier for the sensor instance"
                                            ],
                                            target: [
                                              type: {:custom, __MODULE__, :validate_target, []},
                                              required: true,
                                              doc:
                                                "Target for signal delivery. Can be a single dispatch config tuple or a keyword list of named configurations."
                                            ],
                                            retain_last: [
                                              type: :pos_integer,
                                              default: 10,
                                              doc: "Number of last values to retain"
                                            ]
                                          ] ++ @validated_opts[:schema]
                                        )

          @doc """
          Returns the configured name of the sensor.
          """
          @spec name() :: String.t()
          def name, do: @validated_opts[:name]

          @doc """
          Returns the configured description of the sensor.
          """
          @spec description() :: String.t() | nil
          def description, do: @validated_opts[:description]

          @doc """
          Returns the configured category of the sensor.
          """
          @spec category() :: atom() | nil
          def category, do: @validated_opts[:category]

          @doc """
          Returns the configured tags for the sensor.
          """
          @spec tags() :: [atom()]
          def tags, do: @validated_opts[:tags]

          @doc """
          Returns the configured version of the sensor.
          """
          @spec vsn() :: String.t() | nil
          def vsn, do: @validated_opts[:vsn]

          @doc """
          Returns the configured schema for the sensor.
          """
          @spec schema() :: Keyword.t()
          def schema, do: @validated_opts[:schema]

          @doc """
          Converts the sensor metadata to a JSON-compatible map.

          Returns a map containing the sensor's name, description, category, tags,
          version and schema configuration.

          ## Example

              iex> MySensor.to_json()
              %{
                name: "my_sensor",
                description: "A test sensor",
                category: :test,
                tags: [:test, :example],
                vsn: "1.0.0",
                schema: []
              }
          """
          @spec to_json() :: map()
          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              schema: @validated_opts[:schema]
            }
          end

          @doc false
          @spec __sensor_metadata__() :: map()
          def __sensor_metadata__ do
            to_json()
          end

          @doc """
          Starts a new Sensor process.

          ## Options

          #{NimbleOptions.docs(@sensor_server_options_schema)}

          ## Return Values

            * `{:ok, pid}` - The sensor was started successfully
            * `{:error, reason}` - The sensor failed to start

          ## Examples

              iex> MySensor.start_link(id: "sensor1", target: {:bus, :my_bus})
              {:ok, #PID<0.123.0>}

              iex> MySensor.start_link(id: "sensor1", target: {:invalid, :target})
              {:error, "invalid target specification"}
          """
          @spec start_link(Keyword.t()) :: GenServer.on_start()
          def start_link(opts) do
            {id, opts} = Keyword.pop(opts, :id, Jido.Util.generate_id())
            opts = Keyword.put(opts, :id, id)

            case validate_config(opts) do
              {:ok, validated_opts} ->
                GenServer.start_link(__MODULE__, validated_opts)

              {:error, _} = error ->
                error
            end
          end

          def child_spec(opts) do
            %{
              id: __MODULE__,
              start: {__MODULE__, :start_link, [opts]},
              shutdown: 5000,
              restart: :permanent,
              type: :worker
            }
          end

          @doc """
          Retrieves the complete configuration of a sensor.

          ## Parameters
            * `sensor` - The sensor to get configuration from. Can be a PID, atom name, or string name.

          ## Return Values
            * `{:ok, config}` - The complete configuration map
            * `{:error, reason}` - If the sensor cannot be found or accessed

          ## Examples

              iex> {:ok, config} = MySensor.get_config(sensor_pid)
              {:ok, %{id: "sensor1", target: {:bus, :my_bus}}}

              iex> MySensor.get_config(:nonexistent_sensor)
              {:error, :invalid_sensor}
          """
          @spec get_config(Sensor.t()) :: {:ok, map()} | {:error, any()}
          def get_config(sensor) do
            case resolve_sensor(sensor) do
              {:ok, pid} -> GenServer.call(pid, :get_all_config)
              error -> error
            end
          end

          @doc """
          Retrieves a specific configuration value from a sensor.

          ## Parameters
            * `sensor` - The sensor to get configuration from. Can be a PID, atom name, or string name.
            * `key` - The configuration key to retrieve

          ## Return Values
            * `{:ok, value}` - The configuration value for the key
            * `{:error, :not_found}` - If the key does not exist
            * `{:error, reason}` - If the sensor cannot be found or accessed

          ## Examples

              iex> {:ok, value} = MySensor.get_config(sensor_pid, :target)
              {:ok, {:bus, :my_bus}}

              iex> MySensor.get_config(sensor_pid, :nonexistent_key)
              {:error, :not_found}
          """
          @spec get_config(Sensor.t(), atom()) :: {:ok, any()} | {:error, :not_found | any()}
          def get_config(sensor, key) do
            case resolve_sensor(sensor) do
              {:ok, pid} -> GenServer.call(pid, {:get_config, key})
              error -> error
            end
          end

          @doc """
          Updates multiple configuration values for a sensor.

          ## Parameters
            * `sensor` - The sensor to update. Can be a PID, atom name, or string name.
            * `config` - A map containing the configuration key-value pairs to update

          ## Return Values
            * `:ok` - The configuration was updated successfully
            * `{:error, reason}` - If the sensor cannot be found or accessed

          ## Examples

              iex> MySensor.set_config(sensor_pid, %{key1: "value1", key2: "value2"})
              :ok

              iex> MySensor.set_config(:nonexistent_sensor, %{key: "value"})
              {:error, :invalid_sensor}
          """
          @spec set_config(Sensor.t(), map()) :: :ok | {:error, any()}
          def set_config(sensor, config) when is_map(config) do
            case resolve_sensor(sensor) do
              {:ok, pid} -> GenServer.call(pid, {:set_config, config})
              error -> error
            end
          end

          @doc """
          Updates a single configuration value for a sensor.

          ## Parameters
            * `sensor` - The sensor to update. Can be a PID, atom name, or string name.
            * `key` - The configuration key to update
            * `value` - The new value to set

          ## Return Values
            * `:ok` - The configuration was updated successfully
            * `{:error, reason}` - If the sensor cannot be found or accessed

          ## Examples

              iex> MySensor.set_config(sensor_pid, :some_key, "new_value")
              :ok

              iex> MySensor.set_config(:nonexistent_sensor, :key, "value")
              {:error, :invalid_sensor}
          """
          @spec set_config(Sensor.t(), atom(), any()) :: :ok | {:error, any()}
          def set_config(sensor, key, value) do
            case resolve_sensor(sensor) do
              {:ok, pid} -> GenServer.call(pid, {:set_config, key, value})
              error -> error
            end
          end

          @impl GenServer
          def init(opts) do
            Process.flag(:trap_exit, true)

            with {:ok, validated_opts} <- validate_config(opts),
                 {:ok, mount_state} <- mount(validated_opts) do
              state =
                Map.merge(mount_state, %{
                  id: validated_opts.id,
                  target: validated_opts.target,
                  sensor: struct(Sensor, @validated_opts),
                  last_values: :queue.new(),
                  retain_last: validated_opts.retain_last,
                  config: Map.drop(validated_opts, [:id, :target, :retain_last])
                })

              {:ok, state}
            end
          end

          @impl GenServer
          def handle_call({:set_config, config}, _from, state) when is_map(config) do
            new_state = Map.update!(state, :config, &Map.merge(&1, config))
            {:reply, :ok, new_state}
          end

          @impl GenServer
          def handle_call({:set_config, key, value}, _from, state) do
            new_state = put_in(state.config[key], value)
            {:reply, :ok, new_state}
          end

          @impl GenServer
          def handle_call({:get_config, key}, _from, state) do
            case Map.get(state.config, key) do
              nil -> {:reply, {:error, :not_found}, state}
              value -> {:reply, {:ok, value}, state}
            end
          end

          @impl GenServer
          def handle_call(:get_all_config, _from, state) do
            {:reply, {:ok, state.config}, state}
          end

          @impl true
          @spec mount(map()) :: {:ok, map()} | {:error, any()}
          def mount(opts), do: OK.success(opts)

          @impl true
          @spec deliver_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
          def deliver_signal(state) do
            OK.success(
              Jido.Signal.new(%{
                topic: "signal",
                data: %{status: :ok}
              })
            )
          end

          @impl true
          @spec on_before_deliver(Jido.Signal.t(), map()) ::
                  {:ok, Jido.Signal.t()} | {:error, any()}
          def on_before_deliver(signal, _state), do: OK.success(signal)

          @impl true
          @spec shutdown(map()) :: {:ok, map()} | {:error, any()}
          def shutdown(state), do: OK.success(state)

          @impl GenServer
          def terminate(_reason, state) do
            shutdown(state)
          end

          defp validate_config(opts) when is_list(opts) do
            case NimbleOptions.validate(opts, @sensor_server_options_schema) do
              {:ok, validated} ->
                {:ok, Map.new(validated)}

              {:error, %NimbleOptions.ValidationError{} = error} ->
                {:error, Exception.message(error)}
            end
          end

          defp validate_config(opts) when is_map(opts) do
            validate_config(Map.to_list(opts))
          end

          defp deliver_signal(%Jido.Signal{} = signal, state) do
            Jido.Signal.Dispatch.dispatch(signal, state.target)
          end

          defp update_last_values(state, signal) do
            new_queue = :queue.in(signal, state.last_values)

            new_queue =
              if :queue.len(new_queue) > state.retain_last do
                {_, q} = :queue.out(new_queue)
                q
              else
                new_queue
              end

            %{state | last_values: new_queue}
          end

          defp resolve_sensor(sensor) when is_pid(sensor), do: {:ok, sensor}
          defp resolve_sensor(sensor) when is_atom(sensor), do: {:ok, Process.whereis(sensor)}

          defp resolve_sensor(sensor) when is_binary(sensor),
            do: {:ok, Process.whereis(String.to_atom(sensor))}

          defp resolve_sensor(_), do: {:error, :invalid_sensor}

          defoverridable mount: 1,
                         deliver_signal: 1,
                         on_before_deliver: 2,
                         shutdown: 1

          @doc false
          def validate_target(value) do
            case Jido.Signal.Dispatch.validate_opts(value) do
              {:ok, validated} ->
                {:ok, validated}

              {:error, _reason} ->
                {:error,
                 "invalid dispatch configuration - must be a valid dispatch config tuple or keyword list"}
            end
          end

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Sensor", __MODULE__)

          raise CompileError,
            description: message,
            file: __ENV__.file,
            line: __ENV__.line
      end
    end
  end

  @doc false
  @spec validate_sensor_config!(module(), Keyword.t()) :: t() | {:error, Error.t()}
  def validate_sensor_config!(_module, opts) do
    case NimbleOptions.validate(opts, @sensor_compiletime_options_schema) do
      {:ok, config} ->
        struct!(__MODULE__, Map.new(config))

      {:error, %NimbleOptions.ValidationError{} = error} ->
        error
        |> Error.format_nimble_validation_error("Sensor", __MODULE__)
        |> Error.config_error()
        |> OK.failure()
    end
  end
end
