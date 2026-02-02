defmodule Jido.Agent.Strategy do
  @moduledoc """
  Behaviour for agent execution strategies.

  A Strategy decides how to execute actions in `cmd/2`. The default strategy
  (`Direct`) simply executes actions immediately. Advanced strategies can
  implement behavior trees, LLM chains of thought, or other execution patterns.

  ## Core Contract

  Strategies implement these callbacks:

      cmd(agent, action, context) :: {agent, directives}
      init(agent, context) :: {agent, directives}
      tick(agent, context) :: {agent, directives}
      snapshot(agent, context) :: Strategy.Snapshot.t()

  The `cmd/3` callback is required. Others are optional with default implementations.

  ## Lifecycle

  - `init/2` - Called by AgentServer after `MyAgent.new/1` and before the first `cmd/2`.
    Use this to initialize strategy-specific state.
  - `cmd/3` - Called by `MyAgent.cmd/2` to execute actions.
  - `tick/2` - Called by AgentServer when a strategy has scheduled a tick
    (via `{:schedule, ms, :strategy_tick}`). Use for multi-step execution.

  ## Snapshot Interface

  To avoid agents inspecting strategy internals, strategies expose their state
  through `snapshot/2` which returns a `Strategy.Snapshot` struct:

      snap = MyStrategy.snapshot(agent, ctx)
      if snap.done?, do: snap.result

  This provides a stable interface regardless of internal implementation.

  ## Usage

  Set strategy at compile time:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          strategy: Jido.Agent.Strategy.Direct  # default
      end

      # Or with options:
      defmodule MyBTAgent do
        use Jido.Agent,
          name: "bt_agent",
          strategy: {MyBehaviorTreeStrategy, max_depth: 5}
      end

  ## Built-in Strategies

  - `Jido.Agent.Strategy.Direct` - Execute actions immediately (default)

  ## Custom Strategies

  Use the module and implement the required `cmd/3` callback:

      defmodule MyCustomStrategy do
        use Jido.Agent.Strategy

        @impl true
        def cmd(agent, action, ctx) do
          # Custom execution logic
          # Must return {updated_agent, directives}
        end

        # Optionally override init/2, tick/2, snapshot/2
      end

  Strategy state should live inside `agent.state` under the reserved key
  `:__strategy__`. Use `Jido.Agent.Strategy.State` helpers to manage it.
  """

  alias Jido.Action.Tool, as: ActionTool
  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState

  @type context :: %{
          agent_module: module(),
          strategy_opts: keyword()
        }

  @type status :: :idle | :running | :waiting | :success | :failure

  @type action_spec :: %{
          optional(:schema) => Zoi.schema() | keyword(),
          optional(:doc) => String.t(),
          optional(:name) => String.t()
        }

  defmodule Snapshot do
    @moduledoc """
    Stable, cross-strategy execution snapshot.

    Use this struct instead of inspecting `agent.state.__strategy__` directly.
    This provides a stable interface that strategies can implement while
    freely evolving their internal state structures.

    ## Fields

    - `status` - Coarse execution status (:idle, :running, :waiting, :success, :failure)
    - `done?` - Whether the strategy has reached a terminal state
    - `result` - The main output (if the strategy produces one)
    - `details` - Additional strategy-specific metadata
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                status: Zoi.atom(description: "Coarse execution status"),
                done?: Zoi.boolean(description: "Whether strategy reached terminal state"),
                result:
                  Zoi.any(description: "Main output if strategy produces one") |> Zoi.optional(),
                details:
                  Zoi.map(Zoi.atom(), Zoi.any(), description: "Strategy-specific metadata")
                  |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns true if the strategy has reached a terminal state."
    @spec terminal?(t()) :: boolean()
    def terminal?(%__MODULE__{status: s}), do: s in [:success, :failure]

    @doc "Returns true if the strategy is currently running."
    @spec running?(t()) :: boolean()
    def running?(%__MODULE__{status: s}), do: s in [:running, :waiting]
  end

  # Deprecated: use Snapshot instead
  defmodule Public do
    @moduledoc false

    @schema Zoi.struct(
              __MODULE__,
              %{
                status: Zoi.atom(description: "Execution status"),
                done?: Zoi.boolean(description: "Whether strategy reached terminal state"),
                result: Zoi.any(description: "Main output") |> Zoi.optional(),
                meta:
                  Zoi.map(Zoi.atom(), Zoi.any(), description: "Additional metadata")
                  |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  @doc """
  Execute instructions against the agent.

  Called by `MyAgent.cmd/2` after normalization. Receives a list of
  already-normalized `Instruction` structs. Must return the updated agent
  and any external directives.

  ## Parameters

    * `agent` - The current agent struct
    * `instructions` - List of normalized `Instruction` structs
    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

    * `{updated_agent, directives}` - The new agent state and external effects
  """
  @callback cmd(agent :: Agent.t(), instructions :: [Jido.Instruction.t()], ctx :: context()) ::
              {Agent.t(), [Agent.directive()]}

  @doc """
  Initialize strategy-specific state for a freshly created Agent.

  Called in two contexts:
  1. By `MyAgent.new/1` to initialize strategy state (directives are dropped)
  2. By `AgentServer` during startup to capture and process init directives

  Since this may be called twice, implementations should be **idempotent** for
  state changes. The second call should return the same state (or recognize
  it's already initialized) while still emitting any desired directives.

  Default implementation is a no-op.

  ## Parameters

    * `agent` - The agent struct (may already have strategy state from `new/1`)
    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

    * `{updated_agent, directives}` - The agent with initialized strategy state
  """
  @callback init(agent :: Agent.t(), ctx :: context()) ::
              {Agent.t(), [Agent.directive()]}

  @doc """
  Tick-based continuation for multi-step or long-running strategies.

  Called by AgentServer when a strategy has indicated it wants to be ticked
  (via a schedule directive like `{:schedule, ms, :strategy_tick}`).
  Default implementation is a no-op.

  ## Parameters

    * `agent` - The current agent struct
    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

    * `{updated_agent, directives}` - The new agent state and external effects
  """
  @callback tick(agent :: Agent.t(), ctx :: context()) ::
              {Agent.t(), [Agent.directive()]}

  @doc """
  Returns a stable snapshot of the strategy state.

  Strategies should map any internal fields (status enums, final answers, etc.)
  into a `Strategy.Snapshot` struct. Callers must not depend on internal
  `__strategy__` state shape.

  Default implementation uses `Strategy.State` helpers.

  ## Parameters

    * `agent` - The current agent struct
    * `context` - Execution context

  ## Returns

    * `Strategy.Snapshot.t()` - Snapshot of strategy state
  """
  @callback snapshot(agent :: Agent.t(), ctx :: context()) :: Snapshot.t()

  @doc """
  Returns the schema/spec for a strategy action.

  When a strategy handles internal actions (like `:react_start`), this callback
  provides the schema for parameter normalization. If the action has a schema,
  params will be coerced/normalized before the strategy receives them.

  Return `nil` for actions that don't need normalization.

  ## Parameters

    * `action` - The action atom or module

  ## Returns

    * `action_spec()` - Map with optional `:schema`, `:doc`, `:name` keys
    * `nil` - If no normalization needed
  """
  @callback action_spec(action :: term()) :: action_spec() | nil

  @type signal_target ::
          {:strategy_cmd, action :: term()}
          | {:strategy_tick}
          | {:custom, term()}

  @doc """
  Declares signal routes handled by this strategy.

  Returns a list of route specs that map signal types to strategy commands.
  AgentServer consults this to route incoming signals to the appropriate actions.

  ## Route Targets

  - `{:strategy_cmd, action}` - Call `cmd(agent, [{action, signal.data}])`
  - `{:strategy_tick}` - Schedule a strategy tick
  - `{:custom, term}` - Custom handling (for extension)

  ## Parameters

    * `context` - Execution context with `:agent_module` and `:strategy_opts`

  ## Returns

  List of route specs:
  - `{signal_type, target}` - Route with default priority
  - `{signal_type, target, priority}` - Route with custom priority
  - `{signal_type, match_fn, target}` - Route with pattern matching
  - `{signal_type, match_fn, target, priority}` - Full route spec

  ## Examples

      def signal_routes(_ctx) do
        [
          {"react.user_query", {:strategy_cmd, :react_start}},
          {"ai.llm_result", {:strategy_cmd, :react_llm_result}},
          {"ai.tool_result", {:strategy_cmd, :react_tool_result}}
        ]
      end
  """
  @callback signal_routes(ctx :: context()) :: [
              {String.t(), signal_target()}
              | {String.t(), signal_target(), integer()}
              | {String.t(), (Jido.Signal.t() -> boolean()), signal_target()}
              | {String.t(), (Jido.Signal.t() -> boolean()), signal_target(), integer()}
            ]

  @optional_callbacks init: 2, tick: 2, snapshot: 2, action_spec: 1, signal_routes: 1

  @doc """
  Default snapshot implementation using Strategy.State helpers.

  Reads status from state and determines terminal status.
  """
  @spec default_snapshot(Agent.t()) :: Snapshot.t()
  def default_snapshot(%Agent{} = agent) do
    state = StratState.get(agent, %{})
    status = StratState.status(agent)
    done? = StratState.terminal?(agent)

    %Snapshot{
      status: status,
      done?: done?,
      result: Map.get(state, :result, nil),
      details: Map.drop(state, [:module, :status, :result, :config])
    }
  end

  @doc """
  Normalizes instruction params using the strategy's action_spec.

  If the strategy implements `action_spec/1` and returns a schema for the
  action, params are normalized (string keys → atoms, type coercion via Zoi).
  Otherwise, only basic string-to-atom key conversion is performed.

  ## Parameters

    * `strategy_mod` - The strategy module
    * `instruction` - The instruction to normalize
    * `ctx` - Execution context

  ## Returns

    * Updated instruction with normalized params
  """
  @spec normalize_instruction(module(), Jido.Instruction.t(), context()) :: Jido.Instruction.t()
  def normalize_instruction(strategy_mod, %Jido.Instruction{} = instr, _ctx) do
    spec =
      if function_exported?(strategy_mod, :action_spec, 1),
        do: strategy_mod.action_spec(instr.action),
        else: nil

    params =
      case spec && spec[:schema] do
        nil ->
          # No schema - leave keys as-is to prevent atom table exhaustion
          instr.params

        schema ->
          normalize_with_schema(instr.params, schema, instr.action)
      end

    %Jido.Instruction{instr | params: params}
  end

  defp normalize_with_schema(params, schema, action) do
    cond do
      is_struct(schema) ->
        # Zoi with coerce: true handles string->atom conversion safely
        # Only schema-defined keys become atoms; unknown keys are stripped
        case Zoi.parse(schema, params) do
          {:ok, v} ->
            v

          {:error, err} ->
            raise ArgumentError, "Invalid params for #{inspect(action)}: #{inspect(err)}"
        end

      is_list(schema) ->
        # ActionTool preserves unknown keys as strings (atom-safe)
        ActionTool.convert_params_using_schema(params, schema)

      true ->
        # No schema - leave keys as-is to prevent atom table exhaustion
        params
    end
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Jido.Agent.Strategy

      @impl true
      @spec init(Jido.Agent.t(), Jido.Agent.Strategy.context()) ::
              {Jido.Agent.t(), [Jido.Agent.directive()]}
      def init(agent, _ctx), do: {agent, []}

      @impl true
      @spec tick(Jido.Agent.t(), Jido.Agent.Strategy.context()) ::
              {Jido.Agent.t(), [Jido.Agent.directive()]}
      def tick(agent, _ctx), do: {agent, []}

      @impl true
      @spec snapshot(Jido.Agent.t(), Jido.Agent.Strategy.context()) ::
              Jido.Agent.Strategy.Snapshot.t()
      def snapshot(agent, _ctx), do: unquote(__MODULE__).default_snapshot(agent)

      defoverridable init: 2, tick: 2, snapshot: 2
    end
  end
end

defimpl Inspect, for: Jido.Agent.Strategy.Snapshot do
  def inspect(snapshot, _opts) do
    "#Snapshot<:#{snapshot.status} done?=#{snapshot.done?}>"
  end
end
