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
  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Plugin.Requirements, as: PluginRequirements

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
                           plugins:
                             Zoi.list(Zoi.any(),
                               description: "Plugin modules or {module, config} tuples"
                             )
                             |> Zoi.default([]),
                           default_plugins:
                             Zoi.any(
                               description:
                                 "Override default plugins. false to disable all, or map of %{state_key => false | Module | {Module, config}}"
                             )
                             |> Zoi.optional(),
                           jido:
                             Zoi.atom(
                               description:
                                 "Jido instance module for resolving default plugins at compile time"
                             )
                             |> Zoi.optional()
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

  ## Context

  The context map contains:
  - `agent_module` - The agent module
  - `strategy` - The strategy module
  - `strategy_opts` - Strategy options

  ## Examples

      def signal_routes(_ctx) do
        [
          {"user.created", HandleUserCreatedAction},
          {"counter.increment", IncrementAction},
          {"payment.*", fn s -> s.data.amount > 100 end, LargePaymentAction, 10}
        ]
      end
  """
  @callback signal_routes(ctx :: map()) :: [Jido.Signal.Router.route_spec()]

  @doc """
  Serializes the agent for persistence.

  Called by `Jido.Persist.hibernate/2` before writing to storage.
  The default implementation passes the full agent state through.
  `Jido.Persist` enforces invariants (e.g., stripping `:__thread__`
  and storing a pointer) after this callback returns.

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
    signal_routes: 1,
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
      alias Jido.Plugin.Requirements, as: PluginRequirements

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

      @doc "Returns the merged schema (base + plugin schemas)."
      @spec schema() :: Zoi.schema() | keyword()
      def schema, do: @merged_schema
    end
  end

  @doc false
  @spec __quoted_plugin_accessors__() :: Macro.t()
  def __quoted_plugin_accessors__ do
    basic_plugin_accessors = __quoted_basic_plugin_accessors__()
    computed_plugin_accessors = __quoted_computed_plugin_accessors__()

    quote location: :keep do
      unquote(basic_plugin_accessors)
      unquote(computed_plugin_accessors)
    end
  end

  defp __quoted_basic_plugin_accessors__ do
    quote location: :keep do
      @doc """
      Returns the list of plugin modules attached to this agent (deduplicated).

      For multi-instance plugins, the module appears once regardless of how many
      instances are mounted.

      ## Examples

          iex> #{inspect(__MODULE__)}.plugins()
          [SlackPlugin, OpenAIPlugin]
      """
      @spec plugins() :: [module()]
      def plugins do
        @plugin_instances
        |> Enum.map(& &1.module)
        |> Enum.uniq()
      end

      @doc "Returns the list of plugin specs attached to this agent."
      @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
      def plugin_specs, do: @plugin_specs

      @doc "Returns the list of plugin instances attached to this agent."
      @spec plugin_instances() :: [Jido.Plugin.Instance.t()]
      def plugin_instances, do: @plugin_instances

      @doc "Returns the list of actions from all attached plugins."
      @spec actions() :: [module()]
      def actions, do: @plugin_actions
    end
  end

  defp __quoted_computed_plugin_accessors__ do
    quote location: :keep do
      @doc """
      Returns the union of all capabilities from all mounted plugin instances.

      Capabilities are atoms describing what the agent can do based on its
      mounted plugins.

      ## Examples

          iex> #{inspect(__MODULE__)}.capabilities()
          [:messaging, :channel_management, :chat, :embeddings]
      """
      @spec capabilities() :: [atom()]
      def capabilities do
        @plugin_instances
        |> Enum.flat_map(fn instance -> instance.manifest.capabilities || [] end)
        |> Enum.uniq()
      end

      @doc """
      Returns all expanded route signal types from plugin routes.

      These are the fully-prefixed signal types that the agent can handle.

      ## Examples

          iex> #{inspect(__MODULE__)}.signal_types()
          ["slack.post", "slack.channels.list", "openai.chat", ...]
      """
      @spec signal_types() :: [String.t()]
      def signal_types do
        @validated_plugin_routes
        |> Enum.map(fn {signal_type, _action, _priority} -> signal_type end)
      end

      @doc "Returns the expanded and validated plugin routes."
      @spec plugin_routes() :: [{String.t(), module(), integer()}]
      def plugin_routes, do: @validated_plugin_routes

      @doc "Returns the expanded plugin schedules."
      @spec plugin_schedules() :: [Jido.Plugin.Schedules.schedule_spec()]
      def plugin_schedules, do: @expanded_plugin_schedules
    end
  end

  @doc false
  @spec __quoted_plugin_config_accessors__() :: Macro.t()
  def __quoted_plugin_config_accessors__ do
    plugin_config_public = __quoted_plugin_config_public__()
    plugin_config_helpers = __quoted_plugin_config_helpers__()
    plugin_state_public = __quoted_plugin_state_public__()
    plugin_state_helpers = __quoted_plugin_state_helpers__()

    quote location: :keep do
      unquote(plugin_config_public)
      unquote(plugin_config_helpers)
      unquote(plugin_state_public)
      unquote(plugin_state_helpers)
    end
  end

  defp __quoted_plugin_config_public__ do
    quote location: :keep do
      @doc """
      Returns the configuration for a specific plugin.

      Accepts either a module or a `{module, as_alias}` tuple for multi-instance plugins.
      """
      @spec plugin_config(module() | {module(), atom()}) :: map() | nil
      def plugin_config(plugin_mod) when is_atom(plugin_mod) do
        __find_plugin_config_by_module__(plugin_mod)
      end

      def plugin_config({plugin_mod, as_alias}) when is_atom(plugin_mod) and is_atom(as_alias) do
        case Enum.find(@plugin_instances, &(&1.module == plugin_mod and &1.as == as_alias)) do
          nil -> nil
          instance -> instance.config
        end
      end
    end
  end

  defp __quoted_plugin_config_helpers__ do
    quote location: :keep do
      defp __find_plugin_config_by_module__(plugin_mod) do
        case Enum.find(@plugin_instances, &(&1.module == plugin_mod and is_nil(&1.as))) do
          nil -> __find_plugin_config_fallback__(plugin_mod)
          instance -> instance.config
        end
      end

      defp __find_plugin_config_fallback__(plugin_mod) do
        case Enum.find(@plugin_instances, &(&1.module == plugin_mod)) do
          nil -> nil
          instance -> instance.config
        end
      end
    end
  end

  defp __quoted_plugin_state_public__ do
    quote location: :keep do
      @doc """
      Returns the state slice for a specific plugin.

      Accepts either a module or a `{module, as_alias}` tuple for multi-instance plugins.
      """
      @spec plugin_state(Agent.t(), module() | {module(), atom()}) :: map() | nil
      def plugin_state(agent, plugin_mod) when is_atom(plugin_mod) do
        __find_plugin_state_by_module__(agent, plugin_mod)
      end

      def plugin_state(agent, {plugin_mod, as_alias})
          when is_atom(plugin_mod) and is_atom(as_alias) do
        case Enum.find(@plugin_instances, &(&1.module == plugin_mod and &1.as == as_alias)) do
          nil -> nil
          instance -> Map.get(agent.state, instance.state_key)
        end
      end
    end
  end

  defp __quoted_plugin_state_helpers__ do
    quote location: :keep do
      defp __find_plugin_state_by_module__(agent, plugin_mod) do
        case Enum.find(@plugin_instances, &(&1.module == plugin_mod and is_nil(&1.as))) do
          nil -> __find_plugin_state_fallback__(agent, plugin_mod)
          instance -> Map.get(agent.state, instance.state_key)
        end
      end

      defp __find_plugin_state_fallback__(agent, plugin_mod) do
        case Enum.find(@plugin_instances, &(&1.module == plugin_mod)) do
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
    mount_plugins_fn = __quoted_mount_plugins_definition__()

    quote location: :keep do
      unquote(new_fn)
      unquote(mount_plugins_fn)
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

        # Run plugin mount hooks (pure initialization)
        agent = __mount_plugins__(agent)

        # Run strategy initialization (directives are dropped here;
        # AgentServer handles init directives separately)
        ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
        {initialized_agent, _directives} = strategy().init(agent, ctx)
        initialized_agent
      end

      defp __build_initial_state__(opts) do
        # Build initial state from base schema defaults
        base_defaults = AgentState.defaults_from_schema(@validated_opts[:schema])

        # Build plugin defaults nested under their state_keys
        # Skip plugins with nil schema (they manage their own state lifecycle)
        plugin_defaults =
          @plugin_specs
          |> Enum.reject(fn spec -> spec.schema == nil end)
          |> Enum.map(fn spec ->
            plugin_state_defaults = Jido.Agent.Schema.defaults_from_zoi_schema(spec.schema)
            {spec.state_key, plugin_state_defaults}
          end)
          |> Map.new()

        # Merge: base defaults + plugin defaults + provided state
        schema_defaults = Map.merge(base_defaults, plugin_defaults)
        Map.merge(schema_defaults, opts[:state] || %{})
      end
    end
  end

  defp __quoted_mount_plugins_definition__ do
    quote location: :keep do
      defp __mount_plugins__(agent) do
        Enum.reduce(@plugin_specs, agent, fn spec, agent_acc ->
          __mount_single_plugin__(agent_acc, spec)
        end)
      end

      defp __mount_single_plugin__(agent_acc, spec) do
        mod = spec.module
        config = spec.config || %{}

        case mod.mount(agent_acc, config) do
          {:ok, plugin_state} when is_map(plugin_state) ->
            current_plugin_state = Map.get(agent_acc.state, spec.state_key, %{})
            merged_plugin_state = Map.merge(current_plugin_state, plugin_state)
            new_state = Map.put(agent_acc.state, spec.state_key, merged_plugin_state)
            %{agent_acc | state: new_state}

          {:ok, nil} ->
            agent_acc

          {:error, reason} ->
            raise Jido.Error.internal_error(
                    "Plugin mount failed for #{inspect(mod)}",
                    %{plugin: mod, reason: reason}
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
        * `{MyAction, %{param: 1}, %{context: data}}` - Action with params and context
        * `{MyAction, %{param: 1}, %{}, [timeout: 1000]}` - Action with opts
        * `%Instruction{}` - Full instruction struct
        * `[...]` - List of any of the above (processed in sequence)

      ## Options

      The optional third argument `opts` is a keyword list merged into all instructions:

        * `:timeout` - Maximum time (in ms) for each action to complete
        * `:max_retries` - Maximum retry attempts on failure
        * `:backoff` - Initial backoff time in ms (doubles with each retry)

      ## Examples

          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, MyAction)
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, {MyAction, %{value: 42}})
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, [Action1, Action2])

          # With per-call options (merged into all instructions)
          {agent, directives} = #{inspect(__MODULE__)}.cmd(agent, MyAction, timeout: 5000)
      """
      @spec cmd(Agent.t(), Agent.action()) :: Agent.cmd_result()
      def cmd(%Agent{} = agent, action), do: cmd(agent, action, [])

      @spec cmd(Agent.t(), Agent.action(), keyword()) :: Agent.cmd_result()
      def cmd(%Agent{} = agent, action, opts) when is_list(opts) do
        {:ok, agent, action} = on_before_cmd(agent, action)

        case Instruction.normalize(action, %{state: agent.state}, opts) do
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
    before_after = __quoted_callback_before_after__()
    routes = __quoted_callback_routes__()
    checkpoint = __quoted_callback_checkpoint__()
    restore = __quoted_callback_restore__()
    overridables = __quoted_callback_overridables__()
    helpers = __quoted_callback_helpers__()

    quote location: :keep do
      unquote(before_after)
      unquote(routes)
      unquote(checkpoint)
      unquote(restore)
      unquote(overridables)
      unquote(helpers)
    end
  end

  defp __quoted_callback_before_after__ do
    quote location: :keep do
      # Default callback implementations

      @impl true
      @spec on_before_cmd(Agent.t(), Agent.action()) :: {:ok, Agent.t(), Agent.action()}
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      @spec on_after_cmd(Agent.t(), Agent.action(), [Agent.directive()]) ::
              {:ok, Agent.t(), [Agent.directive()]}
      def on_after_cmd(agent, _action, directives), do: {:ok, agent, directives}
    end
  end

  defp __quoted_callback_routes__ do
    quote location: :keep do
      @impl true
      @spec signal_routes(map()) :: list()
      def signal_routes(_ctx), do: []
    end
  end

  defp __quoted_callback_checkpoint__ do
    quote location: :keep do
      @impl true
      def checkpoint(agent, ctx) do
        {state, externalized, externalized_keys} =
          Enum.reduce(@plugin_instances, {agent.state, %{}, %{}}, fn instance,
                                                                     {state_acc, ext_acc,
                                                                      keys_acc} ->
            plugin_state = Map.get(state_acc, instance.state_key)
            config = instance.config || %{}

            case instance.module.on_checkpoint(plugin_state, Map.put(ctx, :config, config)) do
              {:externalize, key, pointer} ->
                {Map.delete(state_acc, instance.state_key), Map.put(ext_acc, key, pointer),
                 Map.put(keys_acc, key, instance.state_key)}

              :drop ->
                {Map.delete(state_acc, instance.state_key), ext_acc, keys_acc}

              :keep ->
                {state_acc, ext_acc, keys_acc}
            end
          end)

        base = %{
          version: 1,
          agent_module: __MODULE__,
          id: agent.id,
          state: state
        }

        base =
          if externalized_keys == %{},
            do: base,
            else: Map.put(base, :externalized_keys, externalized_keys)

        {:ok, Map.merge(base, externalized)}
      end
    end
  end

  defp __quoted_callback_restore__ do
    quote location: :keep do
      @impl true
      def restore(data, ctx) do
        result =
          case new(id: data[:id] || data["id"]) do
            {:ok, agent} -> {:ok, agent}
            agent when is_struct(agent) -> {:ok, agent}
            {:error, _} = error -> error
          end

        case result do
          {:ok, agent} ->
            base_state = data[:state] || data["state"] || %{}
            agent = %{agent | state: Map.merge(agent.state, base_state)}
            externalized_keys = data[:externalized_keys] || %{}

            Enum.reduce_while(@plugin_instances, {:ok, agent}, fn instance, {:ok, acc} ->
              config = instance.config || %{}
              restore_ctx = Map.put(ctx, :config, config)

              ext_key =
                Enum.find_value(externalized_keys, fn {k, v} ->
                  if v == instance.state_key, do: k
                end)

              pointer = if ext_key, do: data[ext_key]

              if pointer do
                case instance.module.on_restore(pointer, restore_ctx) do
                  {:ok, nil} ->
                    {:cont, {:ok, acc}}

                  {:ok, restored_state} ->
                    {:cont,
                     {:ok, %{acc | state: Map.put(acc.state, instance.state_key, restored_state)}}}

                  {:error, reason} ->
                    {:halt, {:error, reason}}
                end
              else
                {:cont, {:ok, acc}}
              end
            end)

          error ->
            error
        end
      end
    end
  end

  defp __quoted_callback_overridables__ do
    quote location: :keep do
      defoverridable on_before_cmd: 2,
                     on_after_cmd: 3,
                     checkpoint: 2,
                     restore: 2,
                     signal_routes: 1,
                     name: 0,
                     description: 0,
                     category: 0,
                     tags: 0,
                     vsn: 0,
                     schema: 0,
                     strategy: 0,
                     strategy_opts: 0,
                     plugins: 0,
                     plugin_specs: 0,
                     plugin_instances: 0,
                     actions: 0,
                     capabilities: 0,
                     signal_types: 0,
                     plugin_config: 1,
                     plugin_state: 2,
                     plugin_routes: 0,
                     plugin_schedules: 0
    end
  end

  defp __quoted_callback_helpers__ do
    quote location: :keep do
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
    plugin_accessors = Agent.__quoted_plugin_accessors__()
    plugin_config_accessors = Agent.__quoted_plugin_config_accessors__()
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

        @default_plugin_list Jido.Agent.__resolve_default_plugins__(@validated_opts)
        @all_plugin_decls @default_plugin_list ++ (@validated_opts[:plugins] || [])
        @plugin_instances Jido.Agent.__normalize_plugin_instances__(@all_plugin_decls)

        @singleton_alias_violations @plugin_instances
                                    |> Enum.filter(fn inst ->
                                      inst.module.singleton?() and inst.as != nil
                                    end)
        if @singleton_alias_violations != [] do
          modules =
            Enum.map(@singleton_alias_violations, & &1.module) |> Enum.map(&inspect/1)

          raise CompileError,
            description: "Cannot alias singleton plugins: #{Enum.join(modules, ", ")}",
            file: __ENV__.file,
            line: __ENV__.line
        end

        @singleton_modules @plugin_instances
                           |> Enum.filter(fn inst -> inst.module.singleton?() end)
                           |> Enum.map(& &1.module)
        @duplicate_singletons @singleton_modules -- Enum.uniq(@singleton_modules)
        if @duplicate_singletons != [] do
          raise CompileError,
            description:
              "Duplicate singleton plugins: #{inspect(Enum.uniq(@duplicate_singletons))}",
            file: __ENV__.file,
            line: __ENV__.line
        end

        # Build plugin specs from instances (for backward compatibility)
        @plugin_specs Enum.map(@plugin_instances, fn instance ->
                        instance.module.plugin_spec(instance.config)
                        |> Map.put(:state_key, instance.state_key)
                      end)

        # Validate unique state_keys (now derived from instances)
        @plugin_state_keys Enum.map(@plugin_instances, & &1.state_key)
        @duplicate_keys @plugin_state_keys -- Enum.uniq(@plugin_state_keys)
        if @duplicate_keys != [] do
          raise CompileError,
            description: "Duplicate plugin state_keys: #{inspect(@duplicate_keys)}",
            file: __ENV__.file,
            line: __ENV__.line
        end

        # Validate no collision with base schema keys
        @base_schema_keys Jido.Agent.Schema.known_keys(@validated_opts[:schema])
        @colliding_keys Enum.filter(@plugin_state_keys, &(&1 in @base_schema_keys))
        if @colliding_keys != [] do
          raise CompileError,
            description:
              "Plugin state_keys collide with agent schema: #{inspect(@colliding_keys)}",
            file: __ENV__.file,
            line: __ENV__.line
        end

        # Merge schemas: base schema + nested plugin schemas
        @merged_schema Jido.Agent.Schema.merge_with_plugins(
                         @validated_opts[:schema],
                         @plugin_specs
                       )

        # Aggregate actions from plugins
        @plugin_actions @plugin_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq()

        # Expand routes from all plugin instances
        @expanded_plugin_routes Enum.flat_map(
                                  @plugin_instances,
                                  &Jido.Plugin.Routes.expand_routes/1
                                )

        # Expand schedules from all plugin instances
        @expanded_plugin_schedules Enum.flat_map(
                                     @plugin_instances,
                                     &Jido.Plugin.Schedules.expand_schedules/1
                                   )

        # Generate routes for schedule signal types (low priority)
        @schedule_routes Enum.flat_map(
                           @plugin_instances,
                           &Jido.Plugin.Schedules.schedule_routes/1
                         )

        # Combine routes and schedule routes for conflict detection
        @all_plugin_routes @expanded_plugin_routes ++ @schedule_routes

        @plugin_routes_result Jido.Plugin.Routes.detect_conflicts(@all_plugin_routes)
        case @plugin_routes_result do
          {:error, conflicts} ->
            conflict_list = Enum.join(conflicts, "\n  - ")

            raise CompileError,
              description: "Route conflicts detected:\n  - #{conflict_list}",
              file: __ENV__.file,
              line: __ENV__.line

          {:ok, _routes} ->
            :ok
        end

        @validated_plugin_routes elem(@plugin_routes_result, 1)

        # Validate plugin requirements at compile time
        @plugin_config_map Enum.reduce(@plugin_instances, %{}, fn instance, acc ->
                             Map.put(acc, instance.state_key, instance.config)
                           end)
        @requirements_result Jido.Plugin.Requirements.validate_all_requirements(
                               @plugin_instances,
                               @plugin_config_map
                             )
        case @requirements_result do
          {:error, missing_by_plugin} ->
            error_msg = PluginRequirements.format_error(missing_by_plugin)

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
      unquote(plugin_accessors)
      unquote(plugin_config_accessors)
      unquote(strategy_accessors)
      unquote(new_function)
      unquote(cmd_function)
      unquote(utility_functions)
      unquote(callbacks)
    end
  end

  @doc false
  @spec __normalize_plugin_instances__([module() | {module(), map()}]) :: [PluginInstance.t()]
  def __normalize_plugin_instances__(plugins) do
    Enum.map(plugins, &__validate_and_create_plugin_instance__/1)
  end

  @doc false
  @spec __resolve_default_plugins__(map()) :: [module() | {module(), map()}]
  def __resolve_default_plugins__(agent_opts) do
    jido_module = agent_opts[:jido]

    base_defaults =
      if jido_module != nil and function_exported?(jido_module, :__default_plugins__, 0) do
        jido_module.__default_plugins__()
      else
        Jido.Agent.DefaultPlugins.package_defaults()
      end

    Jido.Agent.DefaultPlugins.apply_agent_overrides(base_defaults, agent_opts[:default_plugins])
  end

  defp __validate_and_create_plugin_instance__(plugin_decl) do
    mod = __extract_plugin_module__(plugin_decl)
    __validate_plugin_module__(mod)
    PluginInstance.new(plugin_decl)
  end

  defp __extract_plugin_module__(m) when is_atom(m), do: m
  defp __extract_plugin_module__({m, _}), do: m

  defp __validate_plugin_module__(mod) do
    case Code.ensure_compiled(mod) do
      {:module, _} -> __validate_plugin_behaviour__(mod)
      {:error, reason} -> __raise_plugin_compile_error__(mod, reason)
    end
  end

  defp __validate_plugin_behaviour__(mod) do
    unless function_exported?(mod, :plugin_spec, 1) do
      raise CompileError,
        description: "#{inspect(mod)} does not implement Jido.Plugin (missing plugin_spec/1)"
    end
  end

  defp __raise_plugin_compile_error__(mod, reason) do
    raise CompileError,
      description: "Plugin #{inspect(mod)} could not be compiled: #{inspect(reason)}"
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
