defmodule Jido.Agent do
  @moduledoc """
  Defines an Agent within the Jido system.

  An Agent represents a higher-level entity that can plan and execute a series of Actions.
  Agents are defined at compile-time and provide a consistent interface for planning,
  executing, and managing complex workflows.

  ## Features

  - Compile-time configuration validation
  - Runtime input parameter validation
  - Consistent error handling and formatting
  - Extensible lifecycle hooks
  - JSON serialization support
  - Dynamic planning and execution of Action sequences

  ## Usage

  To define a new Agent, use the `Jido.Agent` behavior in your module:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "Performs a complex workflow",
          category: "processing",
          tags: ["example", "demo"],
          vsn: "1.0.0",
          schema: [
            input: [type: :string, required: true]
          ]

        @impl true
        def plan(agent) do
          # Your planning logic here
          {:ok, [MyAction1, MyAction2]}
        end
      end

  ## Callbacks

  Implementing modules must define the following callback:

  - `c:plan/1`: Generates a plan (sequence of Actions) for the Agent to execute.

  """
  use TypedStruct
  alias Jido.Error
  require OK

  @type action :: module() | {module(), map()}

  typedstruct do
    field(:id, String.t())
    field(:name, String.t())
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()])
    field(:vsn, String.t())
    field(:schema, NimbleOptions.schema())
    field(:planner, module())
    field(:runner, module())
    field(:dirty_state?, boolean())
    field(:pending, :queue.queue(action()))
  end

  @agent_compiletime_options_schema NimbleOptions.new!(
                                      name: [
                                        type: {:custom, Jido.Util, :validate_name, []},
                                        required: true,
                                        doc:
                                          "The name of the Agent. Must contain only letters, numbers, and underscores."
                                      ],
                                      description: [
                                        type: :string,
                                        required: false,
                                        doc: "A description of what the Agent does."
                                      ],
                                      category: [
                                        type: :string,
                                        required: false,
                                        doc: "The category of the Agent."
                                      ],
                                      tags: [
                                        type: {:list, :string},
                                        default: [],
                                        doc: "A list of tags associated with the Agent."
                                      ],
                                      vsn: [
                                        type: :string,
                                        required: false,
                                        doc: "The version of the Agent."
                                      ],
                                      planner: [
                                        type: :atom,
                                        required: false,
                                        default: Jido.Planner.Direct,
                                        doc: "Module implementing the Jido.Planner behavior"
                                      ],
                                      runner: [
                                        type: :atom,
                                        required: false,
                                        default: Jido.Runner.Chain,
                                        doc: "Module implementing the Jido.Runner behavior"
                                      ],
                                      schema: [
                                        type: :keyword_list,
                                        default: [],
                                        doc:
                                          "A NimbleOptions schema for validating the Agent's state."
                                      ]
                                    )

  @callback set(t(), attrs :: map() | list()) :: {:ok, t()} | {:error, any()}
  @callback validate(t()) :: {:ok, t()} | {:error, any()}
  @callback plan(t(), command :: atom() | module(), params :: map()) ::
              {:ok, t()} | {:error, any()}
  @callback run(t()) :: {:ok, t()} | {:error, any()}

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@agent_compiletime_options_schema)

    quote location: :keep do
      @behaviour Jido.Agent
      @agent_runtime_schema [
        id: [
          type: :string,
          required: true,
          doc: "The unique identifier for an instance of an Agent."
        ],
        dirty_state?: [
          type: :boolean,
          required: false,
          default: false,
          doc: "Whether the Agent state is dirty, meaning it hasn't been acted upon yet."
        ],
        pending: [
          # Reference to an erlang :queue.queue()
          type: :any,
          required: false,
          default: nil,
          doc: "A queue of pending actions for the Agent."
        ]
      ]
      alias Jido.Agent
      alias Jido.Util
      require OK
      require Logger

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          @struct_keys Keyword.keys(@agent_runtime_schema) ++
                         Keyword.keys(@validated_opts[:schema])
          defstruct @struct_keys

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def planner, do: @validated_opts[:planner]
          def runner, do: @validated_opts[:runner]
          def schema, do: @agent_runtime_schema ++ @validated_opts[:schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              planner: @validated_opts[:planner],
              runner: @validated_opts[:runner],
              schema: @agent_runtime_schema ++ @validated_opts[:schema]
            }
          end

          def __agent_metadata__ do
            to_json()
          end

          @doc """
          Creates a new agent instance with an optional ID.
          If no ID is provided, generates a UUID.
          """
          # @spec new(String.t() | nil) :: t()
          def new(id \\ nil) do
            generated_id = id || Util.generate_id()

            defaults =
              @validated_opts[:schema]
              |> Enum.map(fn {key, opts} -> {key, Keyword.get(opts, :default)} end)
              |> Keyword.put(:id, generated_id)
              |> Keyword.put(:dirty_state?, false)
              |> Keyword.put(:pending, :queue.new())

            struct(__MODULE__, defaults)
          end

          @impl true
          def set(%__MODULE__{} = agent, attrs) when is_map(attrs) or is_list(attrs) do
            if Enum.empty?(attrs) do
              {:ok, agent}
            else
              case do_set(agent, attrs) do
                {:ok, updated_agent} -> {:ok, %{updated_agent | dirty_state?: true}}
                error -> error
              end
            end
          end

          defp do_set(%__MODULE__{} = agent, attrs) when is_map(attrs) or is_list(attrs) do
            merged = DeepMerge.deep_merge(Map.from_struct(agent), Map.new(attrs))
            updated_agent = struct(__MODULE__, merged)

            if Map.equal?(Map.from_struct(agent), Map.from_struct(updated_agent)) do
              {:ok, updated_agent}
            else
              validate(updated_agent)
            end
          end

          @impl true
          def validate(%__MODULE__{} = agent) do
            case NimbleOptions.validate(Map.to_list(Map.from_struct(agent)), schema()) do
              {:ok, validated_opts} -> {:ok, struct(__MODULE__, validated_opts)}
              {:error, error} -> {:error, Agent.format_validation_error(error)}
            end
          end

          @impl true
          def plan(%__MODULE__{} = agent, command \\ :default, params \\ %{}) do
            with planner = planner(),
                 {:ok, actions} <- planner.plan(agent, command, params) do
              new_queue = Enum.reduce(actions, agent.pending, &:queue.in(&1, &2))
              {:ok, %{agent | pending: new_queue, dirty_state?: true}}
            end
          end

          @impl true
          def run(%__MODULE__{} = agent, opts \\ []) do
            pending_actions = :queue.to_list(agent.pending || :queue.new())
            apply_state = Keyword.get(opts, :apply_state, true)
            runner = runner()

            with {:ok, result} <- runner.run(agent, pending_actions, opts) do
              base_updates = %{pending: :queue.new(), dirty_state?: false}

              case {apply_state, agent.dirty_state?} do
                {true, true} ->
                  do_set(agent, Map.from_struct(result))
                  |> OK.map(&struct(&1, base_updates))

                {_, _} ->
                  {:ok, struct(agent, base_updates), result}
              end
            end
          end

          def reset(%__MODULE__{} = agent) do
            {:ok, %{agent | pending: :queue.new()}}
          end

          def pending?(%__MODULE__{} = agent) do
            :queue.len(agent.pending)
          end

          def act(%__MODULE__{} = agent, command \\ :default, params \\ %{}, opts \\ []) do
            apply_state = Keyword.get(opts, :apply_state, true)

            with {:ok, validated_agent} <- validate(agent),
                 {:ok, updated_agent} <-
                   if(apply_state, do: set(validated_agent, params), else: {:ok, validated_agent}),
                 {:ok, planned_agent} <- plan(updated_agent, command, params),
                 {:ok, final_agent} <- run(planned_agent, opts) do
              {:ok, final_agent}
            end
          end

          defoverridable set: 2, validate: 1

        {:error, error} ->
          Logger.warning("Invalid configuration given to use Jido.Agent: #{error}")

          error
          |> Agent.format_config_error()
          |> Error.config_error()
          |> OK.failure()
      end
    end
  end

  @spec format_config_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_config_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    formatted = "Invalid configuration given to use Jido.Agent: #{message}"
    formatted
  end

  def format_config_error(%NimbleOptions.ValidationError{keys_path: keys_path, message: message}) do
    formatted =
      "Invalid configuration given to use Jido.Agent for key #{inspect(keys_path)}: #{message}"

    formatted
  end

  def format_config_error(error) when is_binary(error) do
    error
  end

  def format_config_error(error) do
    inspect(error)
  end

  @spec format_validation_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_validation_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    formatted = "Invalid parameters for Agent: #{message}"
    formatted
  end

  def format_validation_error(%NimbleOptions.ValidationError{
        keys_path: keys_path,
        message: message
      }) do
    formatted = "Invalid parameters for Agent at #{inspect(keys_path)}: #{message}"
    formatted
  end

  def format_validation_error(error) when is_binary(error) do
    error
  end

  def format_validation_error(error) do
    inspect(error)
  end
end
