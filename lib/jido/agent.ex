defmodule Jido.Agent do
  @moduledoc """
  Defines an Agent within the Jido system - a compile-time defined entity for managing complex s
  through a sequence of Actions.

  ## Overview

  An Agent represents a stateful  executor that can plan and execute a series of Actions in a
  type-safe and composable way. Agents provide a consistent interface for orchestrating complex operations
  while maintaining state validation, error handling, and extensibility through lifecycle hooks.

  ## Architecture

  ### Key Concepts
  * Agents are defined at compile-time using the `use Jido.Agent` macro
  * Each Agent instance is created at server with a guaranteed unique ID
  * Agents maintain their own state schema for validation
  * Actions are registered with Agents and executed through a Runner
  * Lifecycle hooks enable customization of validation, planning and execution flows
  * All operations follow a consistent pattern returning `{:ok, result} | {:error, reason}`

  ### Type Safety & Validation
  * Configuration validated at compile-time via NimbleOptions
  * Server state changes validated against defined schema
  * Action modules checked for behavior implementation
  * Consistent return type enforcement across operations

  ### Features
  * Compile-time configuration validation
  * Server parameter validation via NimbleOptions
  * Comprehensive error handling with recovery hooks
  * Extensible lifecycle callbacks for all operations
  * JSON serialization support for persistence
  * Dynamic Action planning and execution
  * State management with validation and dirty tracking

  ## Usage

  ### Basic Example
      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "Performs a complex ",
          category: "processing",
          tags: ["example", "demo"],
          vsn: "1.0.0",
          schema: [
            input: [type: :string, required: true],
            status: [type: :atom, values: [:pending, :running, :complete]]
          ],
          actions: [MyAction1, MyAction2]
      end

      # Create and configure agent
      {:ok, agent} = MyAgent.new()
      {:ok, agent} = MyAgent.set(agent, input: "test data")

      # Plan and execute actions
      {:ok, agent} = MyAgent.plan(agent, MyAction1, %{value: 1})
      {:ok, agent} = MyAgent.run(agent)  # Result stored in agent.result

  ### Customizing Behavior
      defmodule CustomAgent do
        use Jido.Agent,
          name: "custom_agent",
          schema: [status: [type: :atom]]

        # Add pre-execution validation
        def on_before_run(agent) do
          if agent.state.status == :ready do
            {:ok, agent}
          else
            {:error, "Agent not ready"}
          end
        end

        # Custom error recovery
        def on_error(agent, error) do
          Logger.warning("Agent error", error: error)
          {:ok, %{agent | state: %{status: :error}}}
        end
      end

  ## Callbacks

  The following optional callbacks can be implemented to customize agent behavior.
  All callbacks receive the agent struct and return `{:ok, agent} | {:error, reason}`.

  * `on_before_validate_state/1` - Pre-validation processing
  * `on_after_validate_state/1`  - Post-validation processing
  * `on_before_plan/3`           - Pre-planning processing with params
  * `on_before_run/1`            - Pre-execution validation/setup
  * `on_after_run/3`             - Post-execution processing
  * `on_error/2`                 - Error handling and recovery

  Default implementations pass through the agent unchanged.

  ## Important Notes

  Each Agent module defines its own struct type and behavior. Agent functions must be called
  on matching agent structs:


  ```elixir
    # Correct usage:
    agent = MyAgent.new()
    {:ok, agent} = MyAgent.set(agent, attrs)

    # Incorrect usage:
    agent = MyAgent.new()
    {:ok, agent} = OtherAgent.set(agent, attrs)  # Will fail - type mismatch
  ```

  ## Runner Architecture

  The Runner executes actions in the agent's pending_instructions queue.

  * Default implementation: `Jido.Runner.Simple`
  * Custom runners must implement the `Jido.Runner` behavior
  * Runners handle instruction execution and state management
  * Support for different execution strategies (simple, chain, parallel)

  ## Error Handling

  Errors are returned as tagged tuples: `{:error, reason}`

  Common error types:
  * `:validation_error` - Schema/parameter validation failures
  * `:execution_error`  - Action execution failures
  * `:directive_error`  - Directive application failures

  See `Jido.Action` for implementing compatible Actions.

  ## Type Specifications

  * `t()` - The Agent struct type
  * `instruction()` - Single action with params
  * `instructions()` - List of instructions
  * `agent_result()` - `{:ok, t()} | {:error, term()}`
  """
  use TypedStruct
  use Private
  use ExDbug, enabled: false

  alias Jido.{Error, Signal, Instruction}
  alias Jido.Agent.Directive
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.State, as: ServerState

  require OK

  @type instruction :: Instruction.t() | module() | {module(), map()}
  @type instructions :: instruction() | [instruction()]
  @type agent_result :: {:ok, t()} | {:error, Error.t()}
  @type agent_result_with_directives :: {:ok, t(), [Directive.t()]} | {:error, Error.t()}
  @type map_result :: {:ok, map()} | {:error, Error.t()}

  typedstruct do
    field(:id, String.t())
    field(:name, String.t())
    field(:description, String.t())
    field(:category, String.t())
    field(:tags, [String.t()])
    field(:vsn, String.t())
    field(:schema, NimbleOptions.schema())
    field(:actions, [module()], default: [])
    field(:runner, module())
    field(:dirty_state?, boolean(), default: false)
    field(:pending_instructions, :queue.queue(instruction()))
    field(:state, map(), default: %{})
    field(:result, term(), default: nil)
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
                                      actions: [
                                        type: {:list, :atom},
                                        required: false,
                                        default: [],
                                        doc:
                                          "A list of actions that this Agent implements. Actions must implement the Jido.Action behavior."
                                      ],
                                      runner: [
                                        type: :atom,
                                        required: false,
                                        default: Jido.Runner.Simple,
                                        doc: "Module implementing the Jido.Runner behavior"
                                      ],
                                      schema: [
                                        type: :keyword_list,
                                        default: [],
                                        doc:
                                          "A NimbleOptions schema for validating the Agent's state."
                                      ]
                                    )

  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@agent_compiletime_options_schema)

    # credo:disable-for-next-line Credo.Check.Refactor.LongQuoteBlocks
    quote location: :keep do
      @behaviour Jido.Agent
      @type t :: Jido.Agent.t()
      @type instruction :: Jido.Agent.instruction()
      @type instructions :: Jido.Agent.instructions()
      @type agent_result :: Jido.Agent.agent_result()
      @type agent_result_with_directives :: Jido.Agent.agent_result_with_directives()
      @type map_result :: Jido.Agent.map_result()

      @agent_server_schema [
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
        pending_instructions: [
          # Reference to an erlang :queue.queue()
          type: :any,
          required: false,
          default: nil,
          doc: "A queue of pending actions for the Agent."
        ],
        actions: [
          type: {:list, :atom},
          required: false,
          default: [],
          doc:
            "A list of actions that this Agent implements. Actions must implement the Jido.Action behavior."
        ],
        state: [
          type: :any,
          doc: "The current state of the Agent."
        ],
        result: [
          type: :any,
          doc: "The result of the last action executed by the Agent."
        ]
      ]
      use GenServer
      alias Jido.Agent
      alias Jido.Util
      alias Jido.Signal
      alias Jido.Instruction
      alias Jido.Agent.Directive
      require OK
      require Logger

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          @struct_keys Keyword.keys(@agent_server_schema)
          defstruct @struct_keys

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def actions, do: @validated_opts[:actions]
          def runner, do: @validated_opts[:runner]
          def schema, do: @validated_opts[:schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              actions: @validated_opts[:actions],
              runner: @validated_opts[:runner],
              schema: @validated_opts[:schema]
            }
          end

          @doc false
          def __agent_metadata__ do
            to_json()
          end

          @doc false
          def start_link(opts \\ [])

          def start_link(opts) when is_list(opts) do
            id = Keyword.get(opts, :id, Jido.Util.generate_id())
            initial_state = Keyword.get(opts, :initial_state, %{})
            agent = new(id, initial_state)

            opts =
              opts
              |> Keyword.delete(:initial_state)
              |> Keyword.put(:agent, agent)

            Jido.Agent.Server.start_link(opts)
          end

          def start_link(_opts) do
            agent = new()
            Jido.Agent.Server.start_link(agent: agent)
          end

          @doc false
          def child_spec(opts) do
            %{
              id: __MODULE__,
              start: {__MODULE__, :start_link, [opts]}
            }
          end

          @doc false
          def init(opts), do: OK.success(opts)
          @doc false
          def state(agent), do: Jido.Agent.Server.state(agent)

          @doc false
          def call(agent, signal, timeout \\ 5000),
            do: Jido.Agent.Server.call(agent, signal, timeout)

          @doc false
          def cast(agent, signal), do: Jido.Agent.Server.cast(agent, signal)

          @doc """
          Registers a new action module with the Agent at server.

          The action module must implement the `Jido.Action` behavior and will be
          validated before registration.

          ## Parameters
            * `agent` - The Agent struct to update
            * `action_module` - The action module to register

          ## Returns
            * `{:ok, updated_agent}` - Action successfully registered
            * `{:error, term()}` - Registration failed (invalid module)

          ## Example

              {:ok, agent} = MyAgent.register_action(agent, MyApp.Actions.NewAction)
          """
          @spec register_action(t(), module()) :: agent_result()
          def register_action(agent, action_module),
            do: Agent.register_action(agent, action_module)

          @doc """
          Removes a previously registered action module from the Agent.

          ## Parameters
            * `agent` - The Agent struct to update
            * `action_module` - The action module to remove

          ## Returns
            * `{:ok, updated_agent}` - Action successfully deregistered
            * `{:error, term()}` - Deregistration failed

          ## Example

              {:ok, agent} = MyAgent.deregister_action(agent, MyApp.Actions.OldAction)
          """
          @spec deregister_action(t(), module()) :: agent_result()
          def deregister_action(agent, action_module),
            do: Agent.deregister_action(agent, action_module)

          @doc """
          Returns all action modules currently registered with the Agent.

          This includes both compile-time configured actions and server registered ones.
          Actions are returned in registration order (most recently registered first).

          ## Parameters
            * `agent` - The Agent struct to inspect

          ## Returns
            * `[module()]` - List of registered action modules, empty if none

          ## Example

              actions = MyAgent.registered_actions(agent)
              # Returns: [MyAction1, MyAction2]
          """
          @spec registered_actions(t()) :: [module()] | []
          def registered_actions(agent), do: Agent.registered_actions(agent)

          @doc """
          Creates a new agent instance with an optional ID and initial state.

          ## Initialization
          The new agent is initialized with:
            * A unique identifier (provided or auto-generated)
            * Default state values from schema
            * Empty instruction queue
            * Clean state flag (dirty_state?: false)
            * Configured actions from compile-time options
            * Empty result field

          ## ID Generation
          If no ID is provided, a UUIDv4 is generated using namespace-based deterministic generation
          via `Jido.Util.generate_id/0`. The generated ID is guaranteed to be:
            * Unique within the current server
            * Cryptographically secure
            * URL-safe string format

          ## State Initialization
          The initial state is constructed using default values from the compile-time schema:
            * Fields with defaults use their specified values
            * Required fields without defaults are initialized as nil
            * Optional fields without defaults are omitted
            * Unknown fields are ignored
            * Initial state map is merged and validated if provided

          ## Parameters
            * `id` - Optional string ID for the agent. When provided:
              * Must be unique within your system
              * Should be URL-safe
              * Should not exceed 255 characters
              * Is used-as-is without validation
            * `initial_state` - Optional map of initial state values to merge with defaults

          ## Returns
            * `t()` - A new agent struct containing:
              * `:id` - String, provided or generated identifier
              * `:state` - Map, initialized with schema defaults and initial_state
              * `:dirty_state?` - Boolean, set to false
              * `:pending_instructions` - Queue, empty :queue.queue()
              * `:actions` - List, configured action modules from compile-time
              * `:result` - Term, initialized as nil

          ## Examples

              # Create with auto-generated ID
              agent = MyAgent.new()
              agent.id #=> "c4b3f-..." (UUID format)
              agent.dirty_state? #=> false

              # Create with custom ID and initial state
              agent = MyAgent.new("custom_id_123", %{status: :ready})
              agent.id #=> "custom_id_123"
              agent.state.status #=> :ready

              # Schema defaults are applied
              defmodule AgentWithDefaults do
                use Jido.Agent,
                  name: "test",
                  schema: [
                    status: [type: :atom, default: :pending],
                    retries: [type: :integer, default: 3],
                    optional_field: [type: :string]
                  ]
              end

              agent = AgentWithDefaults.new()
              agent.state #=> %{
                status: :pending,     # From default
                retries: 3,          # From default
                optional_field: nil   # No default
              }

          ## Warning
          While IDs are guaranteed unique when auto-generated, the function does not validate
          uniqueness of provided IDs. When supplying custom IDs, you must ensure uniqueness
          within your system's context.

          See `Jido.Util.generate_id/0` for details on ID generation.
          """
          @spec new(id :: String.t() | atom() | nil | keyword(), initial_state :: map() | nil) ::
                  t()
          def new(opts) when is_list(opts) do
            id = Keyword.get(opts, :id)
            initial_state = Keyword.get(opts, :initial_state, %{})
            new(id, initial_state)
          end

          def new(id \\ nil, initial_state \\ %{})

          def new(id, initial_state) when is_atom(id) and not is_nil(id) do
            Logger.warning(
              "Agent IDs should always be strings, got atom #{inspect(id)}. Converting to string. Please update your code to pass string IDs directly."
            )

            new(Atom.to_string(id), initial_state)
          end

          def new(id, initial_state)
              when (is_binary(id) or is_nil(id)) and is_map(initial_state) do
            generated_id = id || Util.generate_id()

            # Extract default values from schema, handling missing defaults
            state_defaults =
              @validated_opts[:schema]
              |> Enum.map(fn {key, opts} ->
                {key, Keyword.get(opts, :default)}
              end)
              |> Map.new()

            # Create base agent struct with initialized values
            base_agent =
              struct(__MODULE__, %{
                id: generated_id,
                state: state_defaults,
                dirty_state?: false,
                pending_instructions: :queue.new(),
                actions: @validated_opts[:actions] || [],
                result: nil
              })

            # Apply and validate initial state if provided
            case set(base_agent, initial_state) do
              {:ok, agent} -> agent
              {:error, _} -> base_agent
            end
          end

          @doc """
          Updates the agent's state by deep merging the provided attributes. The update process:

          1. Deep merges new attributes with existing state
          2. Validates the merged state against schema
          3. Sets dirty_state? flag for tracking changes
          4. Triggers validation callbacks

          ## Parameters
          * `agent` - The agent struct to update
          * `attrs` - Map or keyword list of attributes to merge into state
          * `opts` - Optional keyword list of options:
            * `strict_validation` - Boolean, whether to perform strict validation (default: false)

          ## Returns
          * `{:ok, updated_agent}` - Agent with merged state and dirty_state? = true
          * `{:error, reason}` - If validation fails or callbacks return error

          ## State Management
          * Empty updates return success without changes
          * Updates trigger `on_before_validate_state` and `on_after_validate_state` callbacks
          * Unknown fields are preserved during deep merge
          * Nested updates are supported via deep merging

          ## Field Validation
          Only fields defined in the schema are validated. Unknown fields are preserved during deep merge.

          ## Examples

              # Simple update
              {:ok, agent} = MyAgent.set(agent, status: :running)

              # Deep merge update
              {:ok, agent} = MyAgent.set(agent, %{
                config: %{retries: 3},
                metadata: %{started_at: DateTime.utc_now()}
              })

              # Validation failure
              {:error, "Invalid status value"} = MyAgent.set(agent, status: :invalid)

          See `validate/1` for validation details and `Jido.Agent` callbacks for lifecycle hooks.
          """
          @spec set(t() | Jido.server(), keyword() | map(), keyword()) :: agent_result()
          def set(agent, attrs, opts \\ [])

          def set(%__MODULE__{} = agent, attrs, opts) when is_list(attrs) do
            mapped_attrs = Map.new(attrs)
            set(agent, mapped_attrs, opts)
          end

          def set(%__MODULE__{} = agent, attrs, opts) when is_map(attrs) do
            strict_validation = Keyword.get(opts, :strict_validation, false)

            if Enum.empty?(attrs) do
              OK.success(agent)
            else
              with {:ok, updated_state} <- do_set(agent.state, attrs),
                   agent_to_validate = %{agent | state: updated_state},
                   {:ok, validated_agent} <-
                     validate(agent_to_validate, strict_validation: strict_validation) do
                OK.success(%{validated_agent | dirty_state?: true})
              else
                {:error, error} ->
                  OK.failure(error)
              end
            end
          end

          def set(%__MODULE__{} = agent, attrs, _opts) do
            Error.validation_error(
              "Invalid state update. Expected a map or keyword list, got #{inspect(attrs)}"
            )
            |> OK.failure()
          end

          def set(%_{} = agent, _attrs, _opts) do
            Error.validation_error(
              "Invalid agent type. Expected #{inspect(agent.__struct__)}, got #{inspect(__MODULE__)}"
            )
            |> OK.failure()
          end

          def set(server, attrs, opts) when not is_struct(server) do
            with {:ok, pid} <- Jido.resolve_pid(server),
                 signal <- ServerSignal.cmd_signal(:set, server, attrs, opts) do
              GenServer.call(pid, signal)
            end
          end

          @spec do_set(map(), map() | keyword()) :: map_result()
          defp do_set(state, attrs) when is_map(attrs) do
            merged = DeepMerge.deep_merge(state, Map.new(attrs))
            OK.success(merged)
          end

          @doc """
          Validates the agent's state through a three-phase process:

          1. Executes pre-validation callback (`on_before_validate_state/1`)
          2. Validates known fields against schema using NimbleOptions
          3. Executes post-validation callback (`on_after_validate_state/1`)

          ## Validation Process
          * Only schema-defined fields are validated
          * Unknown fields are preserved unchanged
          * NimbleOptions performs type and constraint checking

          ## Parameters
          * `agent` - The agent struct to validate
          * `opts` - Optional keyword list of options:
            * `strict_validation` - Boolean, whether to perform strict validation (default: false)

          ## Returns
          * `{:ok, validated_agent}` - Agent with validated state
          * `{:error, reason}` - Validation failed with reason

          ## Examples

              # Successful validation with schema
              defmodule MyAgent do
                use Jido.Agent,
                  name: "my_agent",
                  schema: [
                    status: [type: :atom, values: [:pending, :running]],
                    retries: [type: :integer, minimum: 0]
                  ]

                # Optional validation hooks
                def on_before_validate_state(agent) do
                  # Pre-validation logic
                  {:ok, agent}
                end
              end

              {:ok, agent} = MyAgent.validate(agent)

              # Failed validation
              {:error, "Invalid status value"} = MyAgent.validate(%{
                agent | state: %{status: :invalid}
              })

              # Unknown fields preserved
              {:ok, agent} = MyAgent.validate(%{
                agent | state: %{status: :pending, custom_field: "preserved"}
              })

          ## Validation Flow
          1. `on_before_validate_state` - Preprocess state
          2. Schema validation via NimbleOptions
          3. `on_after_validate_state` - Postprocess validated state

          See `NimbleOptions` documentation for supported validation rules.
          """
          @spec validate(t() | Jido.server(), keyword()) :: agent_result()

          def validate(agent, opts \\ [])

          def validate(%__MODULE__{} = agent, opts) do
            strict_validation = Keyword.get(opts, :strict_validation, false)

            with {:ok, before_agent} <- on_before_validate_state(agent),
                 {:ok, validated_state} <-
                   do_validate(before_agent, before_agent.state,
                     strict_validation: strict_validation
                   ),
                 agent_with_valid_state = %{before_agent | state: validated_state},
                 {:ok, final_agent} <- on_after_validate_state(agent_with_valid_state) do
              OK.success(final_agent)
            end
          end

          def validate(%_{} = agent, _opts) do
            Error.validation_error(
              "Invalid agent type. Expected #{agent.__struct__}, got #{__MODULE__}"
            )
            |> OK.failure()
          end

          def validate(server, opts) do
            with {:ok, pid} <- Jido.resolve_pid(server),
                 signal <- ServerSignal.cmd_signal(:validate, server, opts) do
              GenServer.call(pid, signal)
            end
          end

          @spec do_validate(t(), map(), keyword()) :: map_result()
          defp do_validate(%__MODULE__{} = agent, state, opts) do
            schema = schema()
            strict_validation = Keyword.get(opts, :strict_validation, false)

            if Enum.empty?(schema) do
              OK.success(state)
            else
              known_keys = Keyword.keys(schema)
              {known_state, unknown_state} = Map.split(state, known_keys)

              # Return error if strict validation is enabled and unknown fields exist
              if strict_validation && map_size(unknown_state) > 0 do
                Error.validation_error(
                  "Agent state validation failed: Strict validation is enabled but unknown fields were provided. " <>
                    "When strict validation is enabled, only fields defined in the schema are allowed. " <>
                    "Unknown fields: #{inspect(Map.keys(unknown_state))}",
                  %{
                    agent_id: agent.id,
                    schema: schema,
                    provided_state: known_state,
                    unknown_fields: Map.keys(unknown_state)
                  }
                )
                |> OK.failure()
              else
                case NimbleOptions.validate(Enum.to_list(known_state), schema) do
                  {:ok, validated} ->
                    OK.success(Map.merge(unknown_state, Map.new(validated)))

                  {:error, error} ->
                    Error.validation_error(
                      "Agent state validation failed: The provided state does not match the schema requirements. " <>
                        "This could be due to missing required fields, invalid field types, or values outside allowed ranges. " <>
                        "Only fields defined in the schema are validated. " <>
                        "Please check the schema definition and ensure all required fields are present with valid values. " <>
                        "Error: #{error.message}",
                      %{
                        agent_id: agent.id,
                        schema: schema,
                        provided_state: known_state,
                        unknown_fields: Map.keys(unknown_state),
                        validation_error: error
                      }
                    )
                    |> OK.failure()
                end
              end
            end
          end

          @doc """
          Plans one or more actions by adding them to the agent's pending instruction queue.
          Actions must be registered and valid for the agent. Planning updates the `dirty_state?`
          flag and triggers the `on_before_plan` callback.

          ## Action Registration
          * Actions must be registered via `register_action/2`
          * Invalid or unregistered actions fail planning

          ## Parameters
          * `agent` - The agent struct to plan actions for
          * `instructions` - One of (see `Instruction.normalize/2` for details):
            * Single action module
            * Single action tuple {module, params}
            * List of action modules
            * List of {action_module, params} tuples
            * Mixed list of modules and tuples (e.g. [ValidateAction, {ProcessAction, %{file: "data.csv"}}])
          * `context` - Optional map of context data to include in instructions (default: %{})

          ## Planning Process
          1. Normalizes instructions into consistent [{module, params}] format
          2. Validates action registration
          3. Builds `Instruction` structs with params and provided context
          4. Executes on_before_plan callback
          5. Adds instructions to pending queue
          6. Sets dirty_state? flag

          ## Returns
          * `{:ok, updated_agent}` - Agent with updated pending_instructions and dirty_state?
          * `{:error, reason}` - Planning failed

          ## Examples

              # Plan single action
              {:ok, agent} = MyAgent.plan(agent, ProcessAction)

              # Plan single action with params and context
              {:ok, agent} = MyAgent.plan(agent, {ProcessAction, %{file: "data.csv"}}, %{user_id: "123"})

              # Plan multiple actions with shared context
              {:ok, agent} = MyAgent.plan(agent, [
                ValidateAction,
                {ProcessAction, %{file: "data.csv"}},
                {SaveAction, %{path: "/tmp"}}
              ], %{request_id: "abc123"})

              # Validation failures
              {:error, reason} = MyAgent.plan(agent, UnregisteredAction)
              {:error, reason} = MyAgent.plan(agent, [{InvalidAction, %{}}])

          ## Error Handling
          * Unregistered actions return execution error with affected action details
          * Invalid instruction format returns error with expected format details
          * Failed callbacks return error with callback context
          * All errors include agent_id and relevant debugging information

          See `registered_actions/1` for checking available actions and `run/2` for executing planned actions.
          """

          @spec plan(t() | Jido.server(), instructions(), map()) :: agent_result()
          def plan(agent, instructions, context \\ %{})

          def plan(%__MODULE__{} = agent, instructions, context) do
            with {:ok, instruction_structs} <- Instruction.normalize(instructions, context),
                 :ok <- Instruction.validate_allowed_actions(instruction_structs, agent.actions),
                 {:ok, agent} <- on_before_plan(agent, nil, %{}),
                 {:ok, agent} <- enqueue_instructions(agent, instruction_structs) do
              OK.success(%{agent | dirty_state?: true})
            else
              {:error, %{details: %{actions: actions}} = error} ->
                %{
                  error
                  | message:
                      "Action: #{actions |> Enum.join(", ")} not registered with agent #{__MODULE__.name()}"
                }
                |> OK.failure()

              {:error, reason} ->
                OK.failure(reason)
            end
          end

          def plan(%_{} = agent, _instructions, _context) do
            Error.validation_error(
              "Invalid agent type. Expected #{agent.__struct__}, got #{__MODULE__}"
            )
            |> OK.failure()
          end

          def plan(server, instructions, context) do
            with {:ok, pid} <- Jido.resolve_pid(server),
                 signal <- ServerSignal.cmd_signal(:plan, server, instructions, context) do
              GenServer.call(pid, signal)
            end
          end

          defp enqueue_instructions(agent, instructions) do
            new_queue =
              Enum.reduce(instructions, agent.pending_instructions, fn instruction, queue ->
                :queue.in(instruction, queue)
              end)

            OK.success(%{agent | pending_instructions: new_queue, dirty_state?: true})
          end

          @doc """
          Executes pending instructions in the agent's queue through a multi-phase process.

          Instructions are executed with the help of a runner. Review `Jido.Runner` for more information.

          Each phase can modify the agent's state and trigger callbacks.

          ## Execution Flow
          1. Pre-execution callback (`on_before_run/1`)
          2. Runner execution of pending instructions
          3. Post-execution callback (`on_after_run/3`)
          4. Return agent with updated state and result

          ## Parameters
          * `agent` - The agent struct containing pending instructions
          * `opts` - Keyword list of options:
            * `:runner` - Module implementing the Runner behavior (default: agent's configured runner)

          ## State Management

          State modifications are handled through StateModification directives:
          * `:set` - Set a value at a path: `%StateModification{op: :set, path: [:config, :mode], value: :active}`
          * `:update` - Update with function: `%StateModification{op: :update, path: [:counter], value: &(&1 + 1)}`
          * `:delete` - Remove value at path: `%StateModification{op: :delete, path: [:temp_data]}`
          * `:reset` - Set path to nil: `%StateModification{op: :reset, path: [:cache]}`

          ## Directives
          * Directives are applied after runner execution
          * Directives can modify agent state and result, such as adding or removing actions or enqueuing new instructions
          * Review `Jido.Agent.Directive` for more information

          ## Returns
          * `{:ok, updated_agent, directives}` - Execution completed successfully
          * `{:error, %Error{}}` - Execution failed with specific error type:
            * `:execution_error` - Runner execution failed
            * Any other error wrapped as execution_error

          ## Examples

              # Set up your agent, register and plan some actions to fill the instruction queue
              agent = MyAgent.new()
              {:ok, agent} = MyAgent.plan(agent, [BasicAction, {NoSchema, %{value: 2}}])

              # Basic execution with state modification directives
              {:ok, agent, directives} = MyAgent.run(agent)

              # Using custom runner
              {:ok, agent, directives} = MyAgent.run(agent, runner: CustomRunner)

              # Error handling
              case MyAgent.run(agent) do
                {:ok, agent, directives} ->
                  # Success - state updated through directives
                  agent.state

                {:error, %Error{type: :validation_error}} ->
                  # Handle validation failure

                {:error, %Error{type: :execution_error}} ->
                  # Handle execution failure
              end

          ## Callbacks
          * `on_before_run/1` - Pre-execution preparation
          * `on_after_run/3` - Post-execution processing

          See `Jido.Runner` for implementing custom runners and `plan/2` for queueing actions.
          """
          @spec run(t() | Jido.server(), keyword()) :: agent_result_with_directives()
          def run(agent, opts \\ [])

          def run(%__MODULE__{} = agent, opts) do
            runner = Keyword.get(opts, :runner, runner())

            with {:ok, validated_runner} <- Jido.Util.validate_runner(runner),
                 {:ok, agent} <- on_before_run(agent),
                 {:ok, agent, directives} <- validated_runner.run(agent, opts),
                 {:ok, agent} <- on_after_run(agent, agent.result, directives) do
              {:ok, agent, directives}
            else
              {:error, reason} = error ->
                agent_with_error = %{agent | result: reason}
                on_error(agent_with_error, reason)
            end
          end

          def run(%_{} = agent, _opts) do
            Error.validation_error(
              "Invalid agent type. Expected #{agent.__struct__}, got #{__MODULE__}"
            )
            |> OK.failure()
          end

          def run(server, opts) do
            with {:ok, pid} <- Jido.resolve_pid(server),
                 signal <- ServerSignal.cmd_signal(:run, server, opts) do
              GenServer.call(pid, signal)
            end
          end

          @doc """
          Validates, plans and executes instructions for the agent with enhanced error handling and state management.

          ## Parameters
            * `agent` - The agent struct to act on
            * `instructions` - One of:
              * Single action module
              * Single action tuple {module, params}
              * List of action modules
              * List of {action_module, params} tuples
              * Mixed list of modules and tuples (e.g. [ValidateAction, {ProcessAction, %{file: "data.csv"}}])
            * `context` - Map of execution context data (default: %{})
            * `opts` - Keyword list of execution options:
              * `:runner` - Custom runner module (default: agent's configured runner)
              * `:strict_validation` - Enable/disable param validation (default: false)

          ## Command Flow
          1. Optional parameter validation
          2. Instruction normalization
          3. State preparation and merging
          4. Action planning with context
          5. Execution with configured runner
          6. Result processing and state application through directives

          ## Returns
            * `{:ok, updated_agent, directives}` - Command executed successfully
              * State modifications are handled through directives
              * Result stored in agent.result field
            * `{:error, Error.t()}` - Detailed error with context

          ## Examples

              # Basic command with single action
              {:ok, agent, directives} = MyAgent.cmd(agent, ProcessAction)

              # Single action with params
              {:ok, agent, directives} = MyAgent.cmd(agent, {ProcessAction, %{file: "data.csv"}})

              # Multiple actions with context
              {:ok, agent, directives} = MyAgent.cmd(
                agent,
                [
                  ValidateAction,
                  {ProcessAction, %{file: "data.csv"}},
                  StoreAction
                ],
                %{user_id: "123"}
              )

              # With custom options
              {:ok, agent, directives} = MyAgent.cmd(
                agent,
                {ProcessAction, %{file: "data.csv"}},
                %{user_id: "123"},
                runner: CustomRunner
              )

              # Error handling
              case MyAgent.cmd(agent, ProcessAction, %{}) do
                {:ok, updated_agent, directives} ->
                  # Success case - state updated through directives
                  updated_agent.state
                {:error, %Error{type: :validation_error}} ->
                  # Handle validation failure
                {:error, %Error{type: :execution_error}} ->
                  # Handle execution error
              end
          """
          @spec cmd(t() | Jido.server(), instructions(), map(), keyword()) ::
                  agent_result_with_directives()
          def cmd(agent, instructions, attrs \\ %{}, opts \\ [])

          def cmd(%__MODULE__{} = agent, instructions, attrs, opts) do
            strict_validation = Keyword.get(opts, :strict_validation, false)
            runner = Keyword.get(opts, :runner, runner())
            context = Keyword.get(opts, :context, %{})

            with {:ok, agent} <- set(agent, attrs, strict_validation: strict_validation),
                 {:ok, agent} <- plan(agent, instructions, context),
                 {:ok, agent, directives} <- run(agent, opts) do
              {:ok, agent, directives}
            else
              {:error, reason} ->
                on_error(agent, reason)
            end
          end

          def cmd(%_{} = agent, _instructions, _attrs, _opts) do
            Error.validation_error(
              "Invalid agent type. Expected #{agent.__struct__}, got #{__MODULE__}"
            )
            |> OK.failure()
          end

          def cmd(server, instructions, attrs, opts) do
            with {:ok, pid} <- Jido.resolve_pid(server),
                 signal <- ServerSignal.cmd_signal(:cmd, server, {instructions, attrs}, opts) do
              GenServer.call(pid, signal)
            end
          end

          @doc """
          Resets the agent's pending action queue.

          ## Parameters
            - agent: The agent struct to reset

          ## Returns
            - `{:ok, updated_agent}` - Queue was reset successfully
          """
          @spec reset(t()) :: agent_result()
          def reset(%__MODULE__{} = agent) do
            OK.success(%{agent | dirty_state?: false, result: nil})
          end

          @doc """
          Returns the number of pending actions in the agent's pending_instructions queue.

          ## Parameters
            - agent: The agent struct to check

          ## Returns
            - Integer count of pending actions
          """
          @spec pending?(t()) :: non_neg_integer()
          def pending?(%__MODULE__{} = agent) do
            :queue.len(agent.pending_instructions)
          end

          @spec on_before_validate_state(t()) :: agent_result()
          def on_before_validate_state(agent), do: OK.success(agent)

          @spec on_after_validate_state(t()) :: agent_result()
          def on_after_validate_state(agent), do: OK.success(agent)

          @spec on_before_plan(t(), Instruction.instruction_list(), map()) :: agent_result()
          def on_before_plan(agent, _instructions, _context), do: OK.success(agent)

          @spec on_before_run(t()) :: agent_result()
          def on_before_run(agent), do: OK.success(agent)

          @spec on_after_run(t(), map(), [Directive.t()]) :: agent_result()
          def on_after_run(agent, _result, _unapplied_directives), do: OK.success(agent)

          @spec on_error(t(), any()) :: agent_result()
          def on_error(agent, reason), do: OK.failure(reason)

          @spec mount(ServerState.t(), opts :: keyword()) :: agent_result()
          def mount(state, _opts), do: OK.success(state)

          @spec code_change(ServerState.t(), any(), any()) :: agent_result()
          def code_change(state, _old_vsn, _extra), do: OK.success(state)

          @spec shutdown(ServerState.t(), reason :: any()) :: agent_result()
          def shutdown(state, _reason), do: OK.success(state)

          @spec handle_signal(Signal.t(), t()) :: {:ok, Signal.t()} | {:error, any()}
          def handle_signal(signal, _agent), do: OK.success(signal)

          @spec transform_result(Signal.t(), term() | {:ok, term()} | {:error, any()}, t()) ::
                  {:ok, term()} | {:error, any()}
          def transform_result(signal, result, _agent), do: OK.success(result)

          defoverridable start_link: 1,
                         child_spec: 1,
                         init: 1,
                         mount: 2,
                         code_change: 3,
                         shutdown: 2,
                         handle_signal: 2,
                         transform_result: 3,
                         on_before_validate_state: 1,
                         on_after_validate_state: 1,
                         on_before_plan: 3,
                         on_before_run: 1,
                         on_after_run: 3,
                         on_error: 2

        {:error, error} ->
          message = Error.format_nimble_config_error(error, "Agent", __MODULE__)
          raise CompileError, description: message, file: __ENV__.file, line: __ENV__.line
      end
    end
  end

  # In Jido.Agent module:

  @doc """
  Called before validating any state changes to the Agent.
  Allows custom preprocessing of state attributes.
  """
  @callback on_before_validate_state(agent :: t()) :: agent_result()

  @doc """
  Called after state validation but before saving changes.
  Allows post-processing of validated state.
  """
  @callback on_after_validate_state(agent :: t()) :: agent_result()

  @doc """
  Called before planning actions, allows preprocessing of instructions prior to appending to the agent's queue
  """
  @callback on_before_plan(
              agent :: t(),
              instructions :: Instruction.instruction_list(),
              context :: map()
            ) :: agent_result()

  @doc """
  Called after action planning but before execution.
  Allows inspection/modification of planned actions.
  """
  @callback on_before_run(agent :: t()) :: agent_result()

  @doc """
  Called after successful action execution.
  Allows post-processing of execution results.
  """
  @callback on_after_run(agent :: t(), result :: map(), unapplied_directives :: [Directive.t()]) ::
              agent_result()

  @callback on_error(agent :: t(), reason :: any()) ::
              {:ok, t()} | {:error, t()}

  # Server Callbacks
  @callback start_link(opts :: keyword()) :: {:ok, pid()} | {:error, any()}
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()
  @callback mount(agent :: t(), opts :: keyword()) :: {:ok, map()} | {:error, any()}
  @callback shutdown(agent :: t(), reason :: any()) :: {:ok, map()} | {:error, any()}
  @callback handle_signal(signal :: Signal.t(), agent :: t()) ::
              {:ok, Signal.t()} | {:error, any()}
  @callback transform_result(
              signal :: Signal.t(),
              result :: {:ok, term()} | {:error, any()},
              agent :: t()
            ) ::
              {:ok, term()} | {:error, any()}

  @optional_callbacks [
    start_link: 1,
    child_spec: 1,
    mount: 2,
    shutdown: 2,
    handle_signal: 2,
    transform_result: 3,
    on_before_validate_state: 1,
    on_after_validate_state: 1,
    on_before_plan: 3,
    on_before_run: 1,
    on_after_run: 3,
    on_error: 2
  ]

  @doc """
  Raises an error indicating that Agents cannot be defined at server.

  This function exists to prevent misuse of the Agent system, as Agents
  are designed to be defined at compile-time only.

  ## Returns

  Always returns `{:error, reason}` where `reason` is a config error.

  ## Examples

      iex> Jido.Agent.new()
      {:error, %Jido.Error.ConfigurationError{message: "Agents must be implemented as a module utilizing `use Jido.Agent ...`"}}

  """
  @spec new() :: {:error, any()}
  @spec new(String.t()) :: {:error, any()}
  def new, do: new("")

  def new(_id) do
    "Agents must be implemented as a module utilizing `use Jido.Agent ...`"
    |> Error.config_error()
    |> OK.failure()
  end

  @doc """
  Registers one or more action modules with the agent at server. Registered actions
  can be used in planning and execution. Action modules must implement the `Jido.Action`
  behavior and pass validation checks.

  ## Action Requirements
  * Must be valid Elixir modules implementing `Jido.Action` behavior
  * Must be loaded and available at server
  * Must pass validation via `Jido.Util.validate_actions/1`

  ## Parameters
  * `agent` - The agent struct to update
  * `action_module` - Single action module or list of action modules to register

  ## Returns
  * `{:ok, updated_agent}` - Agent struct with newly registered actions prepended
  * `{:error, String.t()}` - If action validation fails

  ## Examples

      # Register single action
      {:ok, agent} = MyAgent.register_action(agent, MyApp.Actions.ProcessFile)

      # Register multiple actions
      {:ok, agent} = MyAgent.register_action(agent, [Action1, Action2])

  ## Server Considerations
  * Actions persist only for the agent's lifecycle
  * Duplicates are prevented during validation
  * Most recently registered actions take precedence

  See `Jido.Action` for implementing actions and `Jido.Util.validate_actions/1` for validation details.
  """
  @spec register_action(t(), module() | [module()]) ::
          {:ok, t()} | {:error, Jido.Error.t()}
  def register_action(agent, action_modules)
      when is_list(action_modules) do
    # Filter out any modules that are already registered
    new_modules = Enum.reject(action_modules, &(&1 in agent.actions))

    case Jido.Util.validate_actions(new_modules) do
      {:ok, validated_modules} ->
        new_actions = validated_modules ++ agent.actions
        OK.success(%{agent | actions: new_actions})

      {:error, reason} ->
        Error.validation_error("Failed to register actions", %{
          agent_id: agent.id,
          actions: action_modules,
          reason: reason
        })
        |> OK.failure()
    end
  end

  def register_action(agent, action_module) do
    register_action(agent, [action_module])
  end

  def deregister_action(agent, action_module) do
    new_actions = Enum.reject(agent.actions, &(&1 == action_module))
    OK.success(%{agent | actions: new_actions})
  end

  @doc """
  Returns all action modules registered with the agent in registration order.
  Includes both compile-time and server-registered actions.

  ## Parameters
  * `agent` - The agent struct to inspect

  ## Returns
  * `[module()]` - Action modules ordered by registration time (newest first)

  ## Examples
      agent = MyAgent.new()
      MyAgent.registered_actions(agent) #=> [DefaultAction, CoreAction]

      {:ok, agent} = MyAgent.register_action(agent, CustomAction)
      MyAgent.registered_actions(agent) #=> [CustomAction, DefaultAction, CoreAction]

  See `register_action/2` for adding actions and `plan/3` for using them.
  """
  @spec registered_actions(t()) :: [module()]
  def registered_actions(agent) do
    agent.actions || []
  end
end
