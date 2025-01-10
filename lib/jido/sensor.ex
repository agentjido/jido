defmodule Jido.Sensor do
  @moduledoc """
  Defines the behavior and implementation for Sensors in the Jido system.

  A Sensor is a GenServer that emits Signals on PubSub based on specific events and retains a configurable number of last values.

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
  - `c:generate_signal/1`: Generates a signal based on the current state.
  - `c:before_publish/2`: Called before a signal is published.
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
          topic: String.t(),
          heartbeat_interval: non_neg_integer(),
          pubsub: module(),
          retain_last: pos_integer()
        ]

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
                                           "A NimbleOptions schema for validating the Sensor's server options."
                                       ]
                                     )

  @callback mount(map()) :: {:ok, map()} | {:error, any()}
  @callback generate_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  @callback before_publish(Jido.Signal.t(), map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  @callback shutdown(map()) :: {:ok, map()} | {:error, any()}

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@sensor_compiletime_options_schema)

    quote location: :keep do
      @behaviour Jido.Sensor

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
                                            pubsub: [
                                              type: :atom,
                                              required: true,
                                              doc: "PubSub module to use"
                                            ],
                                            topic: [
                                              type: :string,
                                              default: "#{@validated_opts[:name]}:${id}",
                                              doc: "PubSub topic for the sensor"
                                            ],
                                            heartbeat_interval: [
                                              type: :non_neg_integer,
                                              default: 10_000,
                                              doc: "Interval in milliseconds between heartbeats"
                                            ],
                                            retain_last: [
                                              type: :pos_integer,
                                              default: 10,
                                              doc: "Number of last values to retain"
                                            ]
                                          ] ++ @validated_opts[:schema]
                                        )

          @doc """
          Starts a new Sensor process.

          ## Options

          #{NimbleOptions.docs(@sensor_server_options_schema)}
          """
          @spec start_link(Keyword.t()) :: GenServer.on_start()
          def start_link(opts) do
            {id, opts} = Keyword.pop(opts, :id, Jido.Util.generate_id())
            GenServer.start_link(__MODULE__, Map.new(Keyword.put(opts, :id, id)))
          end

          @impl GenServer
          def init(opts) do
            Process.flag(:trap_exit, true)

            with {:ok, validated_opts} <- validate_opts(opts),
                 {:ok, mount_state} <- mount(validated_opts) do
              state =
                Map.merge(mount_state, %{
                  id: validated_opts.id,
                  topic: validated_opts.topic,
                  heartbeat_interval: validated_opts.heartbeat_interval,
                  pubsub: validated_opts.pubsub,
                  sensor: struct(Sensor, @validated_opts),
                  last_values: :queue.new(),
                  retain_last: validated_opts.retain_last
                })

              schedule_heartbeat(state)
              {:ok, state}
            end
          end

          @impl GenServer
          def handle_info(:heartbeat, state) do
            with {:ok, signal} <- generate_signal(state),
                 {:ok, validated_signal} <- before_publish(signal, state),
                 :ok <- publish_signal(validated_signal, state) do
              schedule_heartbeat(state)
              {:noreply, state}
            else
              {:error, reason} ->
                Logger.warning("Error generating or publishing signal: #{inspect(reason)}")
                schedule_heartbeat(state)
                {:noreply, state}
            end
          end

          @impl GenServer
          def handle_info({:sensor_signal, signal}, state) do
            new_state = update_last_values(state, signal)
            {:noreply, new_state}
          end

          @impl GenServer
          def handle_info(msg, state) do
            Logger.debug("Received unhandled message: #{inspect(msg)}")
            {:noreply, state}
          end

          @impl GenServer
          def handle_call(:get_last_values, _from, state) do
            {:reply, :queue.to_list(state.last_values), state}
          end

          @impl GenServer
          def terminate(_reason, state) do
            case shutdown(state) do
              {:ok, _} -> :ok
            end
          end

          @doc """
          Returns the last N published values.
          """
          @spec get_last_values(pid(), pos_integer()) :: [Jido.Signal.t()]
          def get_last_values(pid, n \\ 10) do
            pid
            |> GenServer.call(:get_last_values)
            |> Enum.take(n)
          end

          @spec validate_opts(map()) :: {:ok, map()} | {:error, String.t()}
          defp validate_opts(opts) do
            case NimbleOptions.validate(Map.to_list(opts), @sensor_server_options_schema) do
              {:ok, validated} ->
                OK.success(Map.new(validated))

              {:error, %NimbleOptions.ValidationError{} = error} ->
                OK.failure(Error.format_nimble_validation_error(error, "Sensor", __MODULE__))
            end
          end

          @spec schedule_heartbeat(map()) :: reference() | :ok
          defp schedule_heartbeat(%{heartbeat_interval: interval}) when interval > 0 do
            Process.send_after(self(), :heartbeat, interval)
          end

          defp schedule_heartbeat(_), do: :ok

          @spec publish_signal(Jido.Signal.t(), map()) :: :ok | {:error, :publish_failed}
          defp publish_signal(%Jido.Signal{} = signal, state) do
            Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:sensor_signal, signal})
          rescue
            exception ->
              Logger.error("Failed to publish signal: #{inspect(exception)}")
              {:error, :publish_failed}
          end

          @spec update_last_values(map(), Jido.Signal.t()) :: map()
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

          # Default implementations
          @impl true
          @spec mount(map()) :: {:ok, map()} | {:error, any()}
          def mount(opts), do: OK.success(opts)

          @impl true
          @spec generate_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
          def generate_signal(state) do
            OK.success(
              Jido.Signal.new(%{
                source: "#{state.sensor.name}:#{state.id}",
                topic: "heartbeat",
                payload: %{status: :ok},
                timestamp: DateTime.utc_now()
              })
            )
          end

          @impl true
          @spec before_publish(Jido.Signal.t(), map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
          def before_publish(signal, _state), do: OK.success(signal)

          @impl true
          @spec shutdown(map()) :: {:ok, map()} | {:error, any()}
          def shutdown(state), do: OK.success(state)

          @doc """
          Returns metadata about the sensor.
          """
          @spec metadata() :: Sensor.t()
          def metadata, do: struct(Sensor, @validated_opts)

          @doc """
          Converts the sensor metadata to a JSON-compatible map.
          """
          @spec to_json() :: map()
          def to_json do
            metadata()
            |> Map.from_struct()
            |> Map.update!(:tags, &Enum.map(&1, fn tag -> Atom.to_string(tag) end))
            |> Map.update!(:category, &if(&1, do: Atom.to_string(&1)))
          end

          @doc false
          @spec __sensor_metadata__() :: map()
          def __sensor_metadata__ do
            to_json()
          end

          defoverridable mount: 1,
                         generate_signal: 1,
                         handle_info: 2,
                         before_publish: 2,
                         shutdown: 1

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
