defmodule Jido.Agent.Server.Options do
  @moduledoc false

  @valid_log_levels [:debug, :info, :notice, :warning, :error, :critical, :alert, :emergency]

  @server_state_opts_schema NimbleOptions.new!(
                              id: [
                                type: :string,
                                required: true,
                                doc: "The unique identifier for an instance of an Agent."
                              ],
                              agent: [
                                type: {:custom, __MODULE__, :validate_agent_opts, []},
                                required: true,
                                doc: "The Agent struct or module to be managed by this server"
                              ],
                              mode: [
                                type: {:in, [:auto, :step]},
                                default: :auto,
                                doc: "Server execution mode"
                              ],
                              log_level: [
                                type: {:in, @valid_log_levels},
                                default: :info,
                                doc: "Controls the verbosity of agent logs and signals."
                              ],
                              max_queue_size: [
                                type: :non_neg_integer,
                                default: 10_000,
                                doc: "Maximum number of signals that can be queued"
                              ],
                              registry: [
                                type: :atom,
                                default: Jido.Registry,
                                doc: "Registry to register the server process with"
                              ],
                              dispatch: [
                                type: {:custom, __MODULE__, :validate_dispatch_opts, []},
                                default: {:logger, []},
                                doc: "Dispatch configuration for signal routing"
                              ],
                              routes: [
                                type: {:custom, __MODULE__, :validate_route_opts, []},
                                default: [],
                                doc:
                                  "Route specifications for signal routing. Can be a single Route struct, list of Route structs, or list of route spec tuples"
                              ],
                              actions: [
                                type: {:custom, __MODULE__, :validate_actions_opts, []},
                                default: [],
                                doc:
                                  "List of Action modules to register with the agent at startup"
                              ],
                              sensors: [
                                type: {:list, :mod_arg},
                                default: [],
                                doc: "List of sensor modules to load"
                              ],
                              skills: [
                                type: {:list, :atom},
                                default: [],
                                doc: "List of skill modules to load"
                              ],
                              child_specs: [
                                type: {:list, :mod_arg},
                                default: [],
                                doc: "List of child specs to start when the agent is mounted"
                              ]
                            )

  @doc """
  Builds a validated ServerState struct from the provided options.

  ## Parameters

  - `opts` - Keyword list of server options

  ## Returns

  - `{:ok, state}` - Successfully built state
  - `{:error, reason}` - Failed to build state

  ## Example

      iex> Jido.Agent.Server.Options.build_state(
      ...>   agent: agent,
      ...>   name: "agent_1",
      ...>   routes: [{"example.event", signal}],
      ...>   skills: [WeatherSkill],
      ...> )
      {:ok, %ServerState{...}}
  """
  def validate_server_opts(opts) do
    # Known keys from the schema definition
    known_keys = [
      :id,
      :agent,
      :mode,
      :log_level,
      :max_queue_size,
      :registry,
      :dispatch,
      :routes,
      :actions,
      :sensors,
      :skills,
      :child_specs
    ]

    # Split the options into known and unknown
    {known_opts, unknown_opts} = Keyword.split(opts, known_keys)

    case NimbleOptions.validate(known_opts, @server_state_opts_schema) do
      {:ok, validated_opts} ->
        # Merge the validated known options with the unknown options
        merged_opts = Keyword.merge(unknown_opts, validated_opts)

        {:ok, merged_opts}

      {:error, error} ->
        {:error, error}
    end
  end

  def validate_agent_opts(agent, _opts \\ []) do
    cond do
      is_atom(agent) ->
        {:ok, agent}

      is_struct(agent) and function_exported?(agent.__struct__, :new, 2) ->
        {:ok, agent}

      true ->
        {:error, :invalid_agent}
    end
  end

  def validate_dispatch_opts(config, _opts \\ []) do
    case Jido.Signal.Dispatch.validate_opts(config) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def validate_route_opts(routes, _opts \\ []) do
    case Jido.Signal.Router.normalize(routes) do
      {:ok, normalized} ->
        case Jido.Signal.Router.validate(normalized) do
          {:ok, validated} ->
            {:ok, validated}

          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, "Invalid route configuration: #{inspect(reason)}"}
        end

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, "Invalid route format: #{inspect(reason)}"}
    end
  end

  def validate_actions_opts(actions, _opts \\ []) do
    case Jido.Util.validate_actions(actions) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
