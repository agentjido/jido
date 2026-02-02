defmodule Jido.Agent do
  @moduledoc """
  An Agent is an immutable data structure that holds state and can be updated
  via commands. This module provides a minimal, purely functional API:

  - `new/1` - Create a new agent
  - `set/2` - Update state directly
  - `validate/2` - Validate agent state against schema
  - `cmd/2` - Execute actions: `(agent, action) -> {agent, directives}`

  ## Core Pattern

  The fundamental operation is `cmd/2`:

      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

  Key invariants:
  - The returned `agent` is **always complete** — no "apply directives" step needed
  - `directives` are **external effects only** — they never modify agent state
  - `cmd/2` is a **pure function** — given same inputs, always same outputs

  ## Action Formats

  `cmd/2` accepts actions in these forms:

  - `MyAction` - Action module with no params
  - `{MyAction, %{param: value}}` - Action with params
  - `%Instruction{}` - Full instruction struct
  - `[...]` - List of any of the above (processed in sequence)

  ## Directives

  Directives are effect descriptions for the runtime to interpret. They are
  **strictly outbound** - the agent never receives directives as input.

  Directives are bare structs (no tuple wrappers). Built-in directives
  (see `Jido.Agent.Directive`):

  - `%Directive.Emit{}` - Dispatch a signal via `Jido.Signal.Dispatch`
  - `%Directive.Error{}` - Signal an error (wraps `Jido.Error.t()`)
  - `%Directive.Spawn{}` - Spawn a child process
  - `%Directive.Schedule{}` - Schedule a delayed message
  - `%Directive.Stop{}` - Stop the agent process

  The Emit directive integrates with `Jido.Signal` for dispatch:

      # Emit with default dispatch config
      %Directive.Emit{signal: my_signal}

      # Emit to PubSub topic
      %Directive.Emit{signal: my_signal, dispatch: {:pubsub, topic: "events"}}

      # Emit to a specific process
      %Directive.Emit{signal: my_signal, dispatch: {:pid, target: pid}}

  External packages can define custom directive structs without modifying core.

  Directives never modify agent state — that's handled by the returned agent.

  ## Usage

  ### Defining an Agent Module

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "My custom agent",
          schema: [
            status: [type: :atom, default: :idle],
            counter: [type: :integer, default: 0]
          ]
      end

  ### Working with Agents

      # Create a new agent (fully initialized including strategy state)
      agent = MyAgent.new()
      agent = MyAgent.new(id: "custom-id", state: %{counter: 10})

      # Execute actions
      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

      # Update state directly
      {:ok, agent} = MyAgent.set(agent, %{status: :running})

  ## Strategy Initialization

  `new/1` automatically calls `strategy.init/2` to initialize strategy-specific
  state. Any directives returned by strategy init are dropped here since they
  require a runtime to execute. When using `AgentServer`, it handles strategy
  init directives separately during startup.

  ## Lifecycle Hooks

  Agents support two optional callbacks:

  - `on_before_cmd/2` - Called before command processing (pure transformations only)
  - `on_after_cmd/3` - Called after command processing (pure transformations only)

  ## State Schema Types

  Agent supports two schema formats for state validation:

  1. **NimbleOptions schemas** (familiar, legacy):
     ```elixir
     schema: [
       status: [type: :atom, default: :idle],
       counter: [type: :integer, default: 0]
     ]
     ```

  2. **Zoi schemas** (recommended for new code):
     ```elixir
     schema: Zoi.object(%{
       status: Zoi.atom() |> Zoi.default(:idle),
       counter: Zoi.integer() |> Zoi.default(0)
     })
     ```

  Both are handled transparently by the Agent module.

  ## Pure Functional Design

  The Agent struct is immutable. All operations return new agent structs.
  Server/OTP integration is handled separately by `Jido.AgentServer`.
  """

  alias Jido.Action.Schema
  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.State, as: StateHelper
  alias Jido.Error
  alias Jido.Instruction
  alias Jido.Skill.Instance, as: SkillInstance
  alias Jido.Skill.Requirements, as: SkillRequirements

  require OK

  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique agent identifier")
                |> Zoi.optional(),
              name:
                Zoi.string(description: "Agent name")
                |> Zoi.optional(),
              description:
                Zoi.string(description: "Agent description")
                |> Zoi.optional(),
              category:
                Zoi.string(description: "Agent category")
                |> Zoi.optional(),
              tags:
                Zoi.list(Zoi.string(), description: "Tags")
                |> Zoi.default([]),
              vsn:
                Zoi.string(description: "Version")
                |> Zoi.optional(),
              schema:
                Zoi.any(
                  description: "NimbleOptions or Zoi schema for validating the Agent's state"
                )
                |> Zoi.default([]),
              state:
                Zoi.map(description: "Current state")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Agent."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  # Action input types
  @type action :: module() | {module(), map()} | Instruction.t() | [action()]

  # Directive types (external effects only - never modify agent state)
  # See Jido.Agent.Directive for structured payload modules
  @type directive :: Directive.t()

  @type agent_result :: {:ok, t()} | {:error, Error.t()}
  @type cmd_result :: {t(), [directive()]}

  @agent_config_schema Zoi.object(
                         %{
                           name:
                             Zoi.string(
                               description:
                                 "The name of the Agent. Must contain only letters, numbers, and underscores."
                             )
                             |> Zoi.refine({Jido.Util, :validate_name, []}),
                           description:
                             Zoi.string(description: "A description of what the Agent does.")
                             |> Zoi.optional(),
                           category:
                             Zoi.string(description: "The category of the Agent.")
                             |> Zoi.optional(),
                           tags:
                             Zoi.list(Zoi.string(), description: "Tags")
                             |> Zoi.default([]),
                           vsn:
                             Zoi.string(description: "Version")
                             |> Zoi.optional(),
                           schema:
                             Zoi.any(
                               description:
                                 "NimbleOptions or Zoi schema for validating the Agent's state."
                             )
                             |> Zoi.refine({Schema, :validate_config_schema, []})
                             |> Zoi.default([]),
                           strategy:
                             Zoi.any(
                               description:
                                 "Execution strategy module or {module, opts}. Default: Jido.Agent.Strategy.Direct"
                             )
                             |> Zoi.default(Jido.Agent.Strategy.Direct),
                           skills:
                             Zoi.list(Zoi.any(),
                               description: "Skill modules or {module, config} tuples"
                             )
                             |> Zoi.default([])
                         },
                         coerce: true
                       )

  @doc false
  @spec config_schema() :: Zoi.schema()
  def config_schema, do: @agent_config_schema

  # Callbacks

  @doc """
  Called before command processing. Can transform the agent or action.
  Must be pure - no side effects. Return `{:ok, agent, action}` to continue.

  This hook runs once per `cmd/2` call, with the action as passed (which may be a list).
  It is not a per-instruction hook.

  Use cases:
  - Mirror action params into agent state (e.g., save last_query before processing)
  - Add default params that depend on current state
  - Enforce invariants or guards before execution
  """
  @callback on_before_cmd(agent :: t(), action :: term()) ::
              {:ok, t(), term()}

  @doc """
  Called after command processing. Can transform the agent or directives.
  Must be pure - no side effects. Return `{:ok, agent, directives}` to continue.

  Use cases:
  - Auto-validate state after changes
  - Derive computed fields
  - Add invariant checks
  """
  @callback on_after_cmd(agent :: t(), action :: term(), directives :: [directive()]) ::
              {:ok, t(), [directive()]}

  @doc """
  Returns signal routes for this agent.

  Routes map signal types to action modules. AgentServer uses these routes
  to map incoming signals to actions for execution via cmd/2.

  ## Route Formats

  - `{path, ActionModule}` - Simple mapping (priority 0)
  - `{path, ActionModule, priority}` - With priority
  - `{path, {ActionModule, %{static: params}}}` - With static params
  - `{path, match_fn, ActionModule}` - With pattern matching
  - `{path, match_fn, ActionModule, priority}` - Full spec

  ## Examples

      def signal_routes do
        [
          {"user.created", HandleUserCreatedAction},
          {"counter.increment", IncrementAction},
          {"payment.*", fn s -> s.data.amount > 100 end, LargePaymentAction, 10}
        ]
      end
  """
  @callback signal_routes() :: [Jido.Signal.Router.route_spec()]

  @doc """
  Serializes the agent for persistence.

  Called by `Jido.Persist.hibernate/2` before writing to storage.
  The returned data should NOT include the full Thread - only a pointer.

  If not implemented, a default serialization is used that:
  - Excludes `:__thread__` from state
  - Stores thread pointer as `%{id: thread.id, rev: thread.rev}`

  ## Parameters

  - `agent` - The agent to serialize
  - `ctx` - Context map (may contain jido instance, options)

  ## Returns

  - `{:ok, serializable_data}` - Data to persist
  - `{:error, reason}` - Serialization failed
  """
  @callback checkpoint(agent :: t(), ctx :: map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Restores an agent from persisted data.

  Called by `Jido.Persist.thaw/3` after loading from storage.
  The Thread is reattached separately by Persist after restore.

  If not implemented, a default restoration is used that:
  - Creates a new agent with the persisted id
  - Merges the persisted state

  ## Parameters

  - `data` - The persisted data (from checkpoint/2)
  - `ctx` - Context map (may contain jido instance, options)

  ## Returns

  - `{:ok, agent}` - Restored agent (without thread attached)
  - `{:error, reason}` - Restoration failed
  """
  @callback restore(data :: map(), ctx :: map()) :: {:ok, t()} | {:error, term()}

  @optional_callbacks [
    on_before_cmd: 2,
    on_after_cmd: 3,
    signal_routes: 0,
    checkpoint: 2,
    restore: 2
  ]

  # Helper functions that generate quoted code for the __using__ macro.
  # This approach reduces the size of the main quote block to avoid
  # "long quote blocks" and "nested too deep" Credo warnings.

  @doc false
  @spec __quoted_module_setup__() :: Macro.t()
  def __quoted_module_setup__ do
    quote location: :keep do
      @behaviour Jido.Agent

      alias Jido.Agent
      alias Jido.Agent.State, as: AgentState
      alias Jido.Agent.Strategy, as: AgentStrategy
      alias Jido.Instruction
      alias Jido.Skill.Requirements, as: SkillRequirements

      require OK
    end
  end

  @doc false
  @spec __quoted_basic_accessors__() :: Macro.t()
  def __quoted_basic_accessors__ do
    quote location: :keep do
      @doc "Returns the agent's name."
      @spec name() :: String.t()
      def name, do: @validated_opts.name

      @doc "Returns the agent's description."
      @spec description() :: String.t() | nil
      def description, do: @validated_opts[:description]

      @doc "Returns the agent's category."
      @spec category() :: String.t() | nil
      def category, do: @validated_opts[:category]

      @doc "Returns the agent's tags."
      @spec tags() :: [String.t()]
      def tags, do: @validated_opts[:tags] || []

      @doc "Returns the agent's version."
      @spec vsn() :: String.t() | nil
      def vsn, do: @validated_opts[:vsn]

      @doc "Returns the merged schema (base + skill schemas)."
      @spec schema() :: Zoi.schema() | keyword()
      def schema, do: @merged_schema
    end
  end

  @doc false
  @spec __quoted_skill_accessors__() :: Macro.t()
  def __quoted_skill_accessors__ do
    basic_skill_accessors = __quoted_basic_skill_accessors__()
    computed_skill_accessors = __quoted_computed_skill_accessors__()

    quote location: :keep do
      unquote(basic_skill_accessors)
      unquote(computed_skill_accessors)
    end
  end

  defp __quoted_basic_skill_accessors__ do
    quote location: :keep do
      @doc """
      Returns the list of skill modules attached to this agent (deduplicated).

      For multi-instance skills, the module appears once regardless of how many
      instances are mounted.

      ## Examples

          iex> #{inspect(__MODULE__)}.skills()
          [SlackSkill, OpenAISkill]
      """
      @spec skills() :: [module()]
      def skills do
        @skill_instances
        |> Enum.map(& &1.module)
        |> Enum.uniq()
      end

      @doc "Returns the list of skill specs attached to this agent."
      @spec skill_specs() :: [Jido.Skill.Spec.t()]
      def skill_specs, do: @skill_specs

      @doc "Returns the list of skill instances attached to this agent."
      @spec skill_instances() :: [Jido.Skill.Instance.t()]
      def skill_instances, do: @skill_instances

      @doc "Returns the list of actions from all attached skills."
      @spec actions() :: [module()]
      def actions, do: @skill_actions
    end
  end

  defp __quoted_computed_skill_accessors__ do
    quote location: :keep do
      @doc """
      Returns the union of all capabilities from all mounted skill instances.

      Capabilities are atoms describing what the agent can do based on its
      mounted skills.

      ## Examples

          iex> #{inspect(__MODULE__)}.capabilities()
          [:messaging, :channel_management, :chat, :embeddings]
      """
      @spec capabilities() :: [atom()]
      def capabilities do
        @skill_instances
        |> Enum.flat_map(fn instance -> instance.manifest.capabilities || [] end)
        |> Enum.uniq()
      end

      @doc """
      Returns all expanded route signal types from skill routes.

      These are the fully-prefixed signal types that the agent can handle.

      ## Examples

          iex> #{inspect(__MODULE__)}.signal_types()
          ["slack.post", "slack.channels.list", "openai.chat", ...]
      """
      @spec signal_types() :: [String.t()]
      def signal_types do
        @validated_skill_routes
        |> Enum.map(fn {signal_type, _action, _priority} -> signal_type end)
      end

      @doc "Returns the expanded and validated skill routes."
      @spec skill_routes() :: [{String.t(), module(), integer()}]
      def skill_routes, do: @validated_skill_routes

      @doc "Returns the expanded skill schedules."
      @spec skill_schedules() :: [Jido.Skill.Schedules.schedule_spec()]
      def skill_schedules, do: @expanded_skill_schedules
    end
  end

  @doc false
  @spec __quoted_skill_config_accessors__() :: Macro.t()
  def __quoted_skill_config_accessors__ do
    skill_config_public = __quoted_skill_config_public__()
    skill_config_helpers = __quoted_skill_config_helpers__()
    skill_state_public = __quoted_skill_state_public__()
    skill_state_helpers = __quoted_skill_state_helpers__()

    quote location: :keep do
      unquote(skill_config_public)
      unquote(skill_config_helpers)
      unquote(skill_state_public)
      unquote(skill_state_helpers)
    end
  end

  defp __quoted_skill_config_public__ do
    quote location: :keep do
      @doc """
      Returns the configuration for a specific skill.

      Accepts either a module or a `{module, as_alias}` tuple for multi-instance skills.
      """
      @spec skill_config(module() | {module(), atom()}) :: map() | nil
      def skill_config(skill_mod) when is_atom(skill_mod) do
        __find_skill_config_by_module__(skill_mod)
      end

      def skill_config({skill_mod, as_alias}) when is_atom(skill_mod) and is_atom(as_alias) do
        case Enum.find(@skill_instances, &(&1.module == skill_mod and &1.as == as_alias)) do
          nil -> nil
          instance -> instance.config
        end
      end
    end
  end

  defp __quoted_skill_config_helpers__ do
    quote location: :keep do
      defp __find_skill_config_by_module__(skill_mod) do
        case Enum.find(@skill_instances, &(&1.module == skill_mod and is_nil(&1.as))) do
          nil -> __find_skill_config_fallback__(skill_mod)
          instance -> instance.config
        end
      end

      defp __find_skill_config_fallback__(skill_mod) do
        case Enum.find(@skill_instances, &(&1.module == skill_mod)) do
          nil -> nil
          instance -> instance.config
        end
      end
    end
  end

  defp __quoted_skill_state_public__ do
    quote location: :keep do
      @doc """
      Returns the state slice for a specific skill.

      Accepts either a module or a `{module, as_alias}` tuple for multi-instance skills.
      """
      @spec skill_state(Agent.t(), module() | {module(), atom()}) :: map() | nil
      def skill_state(agent, skill_mod) when is_atom(skill_mod) do
        __find_skill_state_by_module__(agent, skill_mod)
      end

      def skill_state(agent, {skill_mod, as_alias})
          when is_atom(skill_mod) and is_atom(as_alias) do
        case Enum.find(@skill_instances, &(&1.module == skill_mod and &1.as == as_alias)) do
          nil -> nil
          instance -> Map.get(agent.state, instance.state_key)
        end
      end
    end
  end

  defp __quoted_skill_state_helpers__ do
    quote location: :keep do
      defp __find_skill_state_by_module__(agent, skill_mod) do
        case Enum.find(@skill_instances, &(&1.module == skill_mod and is_nil(&1.as))) do
          nil -> __find_skill_state_fallback__(agent, skill_mod)
          instance -> Map.get(agent.state, instance.state_key)
        end
      end

      defp __find_skill_state_fallback__(agent, skill_mod) do
        case Enum.find(@skill_instances, &(&1.module == skill_mod)) do
          nil -> nil
          instance -> Map.get(agent.state, instance.state_key)
        end
      end
    end
  end

  @doc false
  @spec __quoted_strategy_accessors__() :: Macro.t()
  def __quoted_strategy_accessors__ do
    quote location: :keep do
      @doc "Returns the execution strategy module for this agent."
      @spec strategy() :: module()
      def strategy do
        case @validated_opts[:strategy] do
          {mod, _opts} -> mod
          mod -> mod
        end
      end

      @doc "Returns the strategy options for this agent."
      @spec strategy_opts() :: keyword()
      def strategy_opts do
        case @validated_opts[:strategy] do
          {_mod, opts} -> opts
          _ -> []
        end
      end
    end
  end

  @doc false
  @spec __quoted_new_function__() :: Macro.t()
  def __quoted_new_function__ do
    new_fn = __quoted_new_fn_definition__()
    mount_skills_fn = __quoted_mount_skills_definition__()

    quote location: :keep do
      unquote(new_fn)
      unquote(mount_skills_fn)
    end
  end

  defp __quoted_new_fn_definition__ do
    quote location: :keep do
      @doc """
      Creates a new agent with optional initial state.

      The agent is fully initialized including strategy state. For the default
      Direct strategy, this is a no-op. For custom strategies, any state
      initialization is applied (but directives are only processed by AgentServer).

      ## Examples

          agent = #{inspect(__MODULE__)}.new()
          agent = #{inspect(__MODULE__)}.new(id: "custom-id")
          agent = #{inspect(__MODULE__)}.new(state: %{counter: 10})
      """
      @spec new(keyword() | map()) :: Agent.t()
      def new(opts \\ []) do
        opts = if is_list(opts), do: Map.new(opts), else: opts

        initial_state = __build_initial_state__(opts)
        id = opts[:id] || Jido.Util.generate_id()

        agent = %Agent{
          id: id,
          name: name(),
          description: description(),
          category: category(),
          tags: tags(),
          vsn: vsn(),
          schema: schema(),
          state: initial_state
        }

        # Run skill mount hooks (pure initialization)
        agent = __mount_skills__(agent)

        # Run strategy initialization (directives are dropped here;
        # AgentServer handles init directives separately)
        ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
        {initialized_agent, _directives} = strategy().init(agent, ctx)
        initialized_agent
      end

      defp __build_initial_state__(opts) do
        # Build initial state from base schema defaults
        base_defaults = AgentState.defaults_from_schema(@validated_opts[:schema])

        # Build skill defaults nested under their state_keys
        skill_defaults =
          @skill_specs
          |> Enum.map(fn spec ->
            skill_state_defaults = Jido.Agent.Schema.defaults_from_zoi_schema(spec.schema)
            {spec.state_key, skill_state_defaults}
          end)
          |> Map.new()

        # Merge: base defaults + skill defaults + provided state
        schema_defaults = Map.merge(base_defaults, skill_defaults)
        Map.merge(schema_defaults, opts[:state] || %{})
      end
    end
  end

  defp __quoted_mount_skills_definition__ do
    quote location: :keep do
      defp __mount_skills__(agent) do
        Enum.reduce(@skill_specs, agent, fn spec, agent_acc ->
          __mount_single_skill__(agent_acc, spec)
        end)
      end

      defp __mount_single_skill__(agent_acc, spec) do
        mod = spec.module
        config = spec.config || %{}

        case mod.mount(agent_acc, config) do
          {:ok, skill_state} when is_map(skill_state) ->
            current_skill_state = Map.get(agent_acc.state, spec.state_key, %{})
            merged_skill_state = Map.merge(current_skill_state, skill_state)
            new_state = Map.put(agent_acc.state, spec.state_key, merged_skill_state)
            %{agent_acc | state: new_state}

          {:ok, nil} ->
            agent_acc

          {:error, reason} ->
            raise Jido.Error.internal_error(
                    "Skill mount failed for #{inspect(mod)}",
                    %{skill: mod, reason: reason}
                  )
        end
      end
    end
  end

  @doc false
  @spec __quoted_cmd_function__() :: Macro.t()
  def __quoted_cmd_function__ do
    quote location: :keep do
      @doc """
      Execute actions against the agent. Pure: `(agent, action) -> {agent, directives}`

      This is the core operation. Actions modify state, directives are external effects.
      Execution is delegated to the configured strategy (default: Direct).

      ## Action Formats

        * `MyAction` - Action module with no params
        * `{MyAction, %{param: 1}}` - Action with params
        * `%Instruction{}` - Full instruction struct
        * `[...]` - List of any of the above (processed in sequence)

      ## Examples

          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, MyAction)
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, {MyAction, %{value: 42}})
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, [Action1, Action2])
      """
      @spec cmd(Agent.t(), Agent.action()) :: Agent.cmd_result()
      def cmd(%Agent{} = agent, action) do
        {:ok, agent, action} = on_before_cmd(agent, action)

        case Instruction.normalize(action, %{state: agent.state}, []) do
          {:ok, instructions} ->
            ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
            strat = strategy()

            normalized_instructions =
              Enum.map(instructions, fn instr ->
                AgentStrategy.normalize_instruction(strat, instr, ctx)
              end)

            {agent, directives} = strat.cmd(agent, normalized_instructions, ctx)
            __do_after_cmd__(agent, action, directives)

          {:error, reason} ->
            error = Jido.Error.validation_error("Invalid action", %{reason: reason})
            {agent, [%Jido.Agent.Directive.Error{error: error, context: :normalize}]}
        end
      end
    end
  end

  @doc false
  @spec __quoted_utility_functions__() :: Macro.t()
  def __quoted_utility_functions__ do
    quote location: :keep do
      @doc """
      Returns a stable, public view of the strategy's execution state.

      Use this instead of inspecting `agent.state.__strategy__` directly.
      Returns a `Jido.Agent.Strategy.Snapshot` struct with:
      - `status` - Coarse execution status
      - `done?` - Whether strategy reached terminal state
      - `result` - Main output if any
      - `details` - Additional strategy-specific metadata
      """
      @spec strategy_snapshot(Agent.t()) :: Jido.Agent.Strategy.Snapshot.t()
      def strategy_snapshot(%Agent{} = agent) do
        ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
        strategy().snapshot(agent, ctx)
      end

      @doc """
      Updates the agent's state by merging new attributes.

      Uses deep merge semantics - nested maps are merged recursively.

      ## Examples

          {:ok, agent} = #{inspect(__MODULE__)}.set(agent, %{status: :running})
          {:ok, agent} = #{inspect(__MODULE__)}.set(agent, counter: 5)
      """
      @spec set(Agent.t(), map() | keyword()) :: Agent.agent_result()
      def set(%Agent{} = agent, attrs) do
        new_state = AgentState.merge(agent.state, Map.new(attrs))
        OK.success(%{agent | state: new_state})
      end

      @doc """
      Validates the agent's state against its schema.

      ## Options
        * `:strict` - When true, only schema-defined fields are kept (default: false)

      ## Examples

          {:ok, agent} = #{inspect(__MODULE__)}.validate(agent)
          {:ok, agent} = #{inspect(__MODULE__)}.validate(agent, strict: true)
      """
      @spec validate(Agent.t(), keyword()) :: Agent.agent_result()
      def validate(%Agent{} = agent, opts \\ []) do
        case AgentState.validate(agent.state, agent.schema, opts) do
          {:ok, validated_state} ->
            OK.success(%{agent | state: validated_state})

          {:error, reason} ->
            Jido.Error.validation_error("State validation failed", %{reason: reason})
            |> OK.failure()
        end
      end
    end
  end

  @doc false
  @spec __quoted_callbacks__() :: Macro.t()
  def __quoted_callbacks__ do
    quote location: :keep do
      # Default callback implementations

      @impl true
      @spec on_before_cmd(Agent.t(), Agent.action()) :: {:ok, Agent.t(), Agent.action()}
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      @spec on_after_cmd(Agent.t(), Agent.action(), [Agent.directive()]) ::
              {:ok, Agent.t(), [Agent.directive()]}
      def on_after_cmd(agent, _action, directives), do: {:ok, agent, directives}

      @impl true
      @spec signal_routes() :: list()
      def signal_routes, do: []

      @impl true
      def checkpoint(agent, _ctx) do
        thread = agent.state[:__thread__]

        {:ok,
         %{
           version: 1,
           agent_module: __MODULE__,
           id: agent.id,
           state: Map.delete(agent.state, :__thread__),
           thread: thread && %{id: thread.id, rev: thread.rev}
         }}
      end

      @impl true
      def restore(data, _ctx) do
        case new(id: data[:id] || data["id"]) do
          {:ok, agent} ->
            state = data[:state] || data["state"] || %{}
            {:ok, %{agent | state: Map.merge(agent.state, state)}}

          error ->
            error
        end
      end

      defoverridable on_before_cmd: 2,
                     on_after_cmd: 3,
                     checkpoint: 2,
                     restore: 2,
                     signal_routes: 0,
                     name: 0,
                     description: 0,
                     category: 0,
                     tags: 0,
                     vsn: 0,
                     schema: 0,
                     strategy: 0,
                     strategy_opts: 0,
                     skills: 0,
                     skill_specs: 0,
                     skill_instances: 0,
                     actions: 0,
                     capabilities: 0,
                     signal_types: 0,
                     skill_config: 1,
                     skill_state: 2,
                     skill_routes: 0,
                     skill_schedules: 0

      # Private helper for after hook dispatch
      defp __do_after_cmd__(agent, msg, directives) do
        {:ok, agent, directives} = on_after_cmd(agent, msg, directives)
        {agent, directives}
      end
    end
  end

  defmacro __using__(opts) do
    # Get the quoted blocks from helper functions
    module_setup = Agent.__quoted_module_setup__()
    basic_accessors = Agent.__quoted_basic_accessors__()
    skill_accessors = Agent.__quoted_skill_accessors__()
    skill_config_accessors = Agent.__quoted_skill_config_accessors__()
    strategy_accessors = Agent.__quoted_strategy_accessors__()
    new_function = Agent.__quoted_new_function__()
    cmd_function = Agent.__quoted_cmd_function__()
    utility_functions = Agent.__quoted_utility_functions__()
    callbacks = Agent.__quoted_callbacks__()

    # Build compile-time validation and module attributes as a separate smaller block
    compile_time_setup =
      quote location: :keep do
        # Validate config at compile time
        @validated_opts (case Zoi.parse(Agent.config_schema(), Map.new(unquote(opts))) do
                           {:ok, validated} ->
                             validated

                           {:error, errors} ->
                             message =
                               "Invalid Agent configuration for #{inspect(__MODULE__)}: #{inspect(errors)}"

                             raise CompileError,
                               description: message,
                               file: __ENV__.file,
                               line: __ENV__.line
                         end)

        # Normalize skills to Instance structs
        @skill_instances Jido.Agent.__normalize_skill_instances__(@validated_opts[:skills] || [])

        # Build skill specs from instances (for backward compatibility)
        @skill_specs Enum.map(@skill_instances, fn instance ->
                       instance.module.skill_spec(instance.config)
                       |> Map.put(:state_key, instance.state_key)
                     end)

        # Validate unique state_keys (now derived from instances)
        @skill_state_keys Enum.map(@skill_instances, & &1.state_key)
        @duplicate_keys @skill_state_keys -- Enum.uniq(@skill_state_keys)
        if @duplicate_keys != [] do
          raise CompileError,
            description: "Duplicate skill state_keys: #{inspect(@duplicate_keys)}",
            file: __ENV__.file,
            line: __ENV__.line
        end

        # Validate no collision with base schema keys
        @base_schema_keys Jido.Agent.Schema.known_keys(@validated_opts[:schema])
        @colliding_keys Enum.filter(@skill_state_keys, &(&1 in @base_schema_keys))
        if @colliding_keys != [] do
          raise CompileError,
            description:
              "Skill state_keys collide with agent schema: #{inspect(@colliding_keys)}",
            file: __ENV__.file,
            line: __ENV__.line
        end

        # Merge schemas: base schema + nested skill schemas
        @merged_schema Jido.Agent.Schema.merge_with_skills(
                         @validated_opts[:schema],
                         @skill_specs
                       )

        # Aggregate actions from skills
        @skill_actions @skill_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq()

        # Expand routes from all skill instances
        @expanded_skill_routes Enum.flat_map(@skill_instances, &Jido.Skill.Routes.expand_routes/1)

        # Expand schedules from all skill instances
        @expanded_skill_schedules Enum.flat_map(
                                    @skill_instances,
                                    &Jido.Skill.Schedules.expand_schedules/1
                                  )

        # Generate routes for schedule signal types (low priority)
        @schedule_routes Enum.flat_map(@skill_instances, &Jido.Skill.Schedules.schedule_routes/1)

        # Combine routes and schedule routes for conflict detection
        @all_skill_routes @expanded_skill_routes ++ @schedule_routes

        @skill_routes_result Jido.Skill.Routes.detect_conflicts(@all_skill_routes)
        case @skill_routes_result do
          {:error, conflicts} ->
            conflict_list = Enum.join(conflicts, "\n  - ")

            raise CompileError,
              description: "Route conflicts detected:\n  - #{conflict_list}",
              file: __ENV__.file,
              line: __ENV__.line

          {:ok, _routes} ->
            :ok
        end

        @validated_skill_routes elem(@skill_routes_result, 1)

        # Validate skill requirements at compile time
        @skill_config_map Enum.reduce(@skill_instances, %{}, fn instance, acc ->
                            Map.put(acc, instance.state_key, instance.config)
                          end)
        @requirements_result Jido.Skill.Requirements.validate_all_requirements(
                               @skill_instances,
                               @skill_config_map
                             )
        case @requirements_result do
          {:error, missing_by_skill} ->
            error_msg = SkillRequirements.format_error(missing_by_skill)

            raise CompileError,
              description: error_msg,
              file: __ENV__.file,
              line: __ENV__.line

          {:ok, :valid} ->
            :ok
        end
      end

    # Combine all blocks using unquote
    quote location: :keep do
      unquote(module_setup)
      unquote(compile_time_setup)
      unquote(basic_accessors)
      unquote(skill_accessors)
      unquote(skill_config_accessors)
      unquote(strategy_accessors)
      unquote(new_function)
      unquote(cmd_function)
      unquote(utility_functions)
      unquote(callbacks)
    end
  end

  @doc false
  @spec __normalize_skill_instances__([module() | {module(), map()}]) :: [SkillInstance.t()]
  def __normalize_skill_instances__(skills) do
    Enum.map(skills, &__validate_and_create_skill_instance__/1)
  end

  defp __validate_and_create_skill_instance__(skill_decl) do
    mod = __extract_skill_module__(skill_decl)
    __validate_skill_module__(mod)
    SkillInstance.new(skill_decl)
  end

  defp __extract_skill_module__(m) when is_atom(m), do: m
  defp __extract_skill_module__({m, _}), do: m

  defp __validate_skill_module__(mod) do
    case Code.ensure_compiled(mod) do
      {:module, _} -> __validate_skill_behaviour__(mod)
      {:error, reason} -> __raise_skill_compile_error__(mod, reason)
    end
  end

  defp __validate_skill_behaviour__(mod) do
    unless function_exported?(mod, :skill_spec, 1) do
      raise CompileError,
        description: "#{inspect(mod)} does not implement Jido.Skill (missing skill_spec/1)"
    end
  end

  defp __raise_skill_compile_error__(mod, reason) do
    raise CompileError,
      description: "Skill #{inspect(mod)} could not be compiled: #{inspect(reason)}"
  end

  # Base module functions (for direct use without `use`)

  @doc """
  Creates a new agent from attributes.

  For module-based agents, use `MyAgent.new/1` instead.
  """
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    attrs_with_id = Map.put_new_lazy(attrs, :id, &Jido.Util.generate_id/0)

    case Zoi.parse(@schema, attrs_with_id) do
      {:ok, agent} ->
        {:ok, agent}

      {:error, errors} ->
        {:error, Error.validation_error("Agent validation failed", %{errors: errors})}
    end
  end

  @doc """
  Updates agent state by merging new attributes.
  """
  @spec set(t(), map() | keyword()) :: agent_result()
  def set(%Agent{} = agent, attrs) do
    new_state = StateHelper.merge(agent.state, Map.new(attrs))
    OK.success(%{agent | state: new_state})
  end

  @doc """
  Validates agent state against its schema.
  """
  @spec validate(t(), keyword()) :: agent_result()
  def validate(%Agent{} = agent, opts \\ []) do
    case StateHelper.validate(agent.state, agent.schema, opts) do
      {:ok, validated_state} ->
        OK.success(%{agent | state: validated_state})

      {:error, reason} ->
        Error.validation_error("State validation failed", %{reason: reason})
        |> OK.failure()
    end
  end
end
