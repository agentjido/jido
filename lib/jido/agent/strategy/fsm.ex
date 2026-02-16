defmodule Jido.Agent.Strategy.FSM do
  @moduledoc """
  A generic finite state machine execution strategy.

  This strategy implements FSM-based workflows where instructions trigger
  state transitions. The FSM state is stored in `agent.state.__strategy__`.

  ## Configuration

  Transitions are configured via strategy options:

      defmodule MyAgent do
        use Jido.Agent,
          name: "fsm_agent",
          strategy: {Jido.Agent.Strategy.FSM,
            initial_state: "idle",
            transitions: %{
              "idle" => ["processing"],
              "processing" => ["idle", "completed", "failed"],
              "completed" => ["idle"],
              "failed" => ["idle"]
            }
          }
      end

  ## Options

  - `:initial_state` - Initial FSM state (default: `"idle"`)
  - `:transitions` - Map of valid transitions `%{from_state => [to_states]}`
  - `:auto_transition` - Whether to auto-transition back to initial state after
    processing (default: `true`)

  ## Default Transitions

  If no transitions are provided, uses a simple workflow:

      %{
        "idle" => ["processing"],
        "processing" => ["idle", "completed", "failed"],
        "completed" => ["idle"],
        "failed" => ["idle"]
      }

  ## States

  Default states (can be customized via transitions):

  - `"idle"` - Initial state, waiting for work
  - `"processing"` - Currently processing instructions
  - `"completed"` - Successfully finished
  - `"failed"` - Terminated with an error

  ## Usage

      agent = MyAgent.new()
      {agent, directives} = MyAgent.cmd(agent, SomeAction)

  The strategy emits `%Directive.RunInstruction{}` directives for runtime execution,
  then handles execution results through internal `cmd/2` actions. This keeps
  strategy `cmd/2` pure while preserving FSM transition semantics.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.StateOps
  alias Jido.Agent.Strategy.InstructionTracking
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Error
  alias Jido.Instruction
  alias Jido.Thread.Agent, as: ThreadAgent

  @default_initial_state "idle"
  @default_transitions %{
    "idle" => ["processing"],
    "processing" => ["idle", "completed", "failed"],
    "completed" => ["idle"],
    "failed" => ["idle"]
  }
  @instruction_result_action :fsm_instruction_result

  defmodule Machine do
    @moduledoc """
    Generic FSM machine that uses configurable transitions.

    Unlike the previous implementation that used Fsmx with hardcoded transitions,
    this module validates transitions dynamically based on the provided config.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                status: Zoi.string(description: "Current FSM state") |> Zoi.default("idle"),
                processed_count:
                  Zoi.integer(description: "Number of processed commands") |> Zoi.default(0),
                last_result: Zoi.any(description: "Result of last command") |> Zoi.optional(),
                error: Zoi.any(description: "Error from last command") |> Zoi.optional(),
                transitions:
                  Zoi.map(Zoi.string(), Zoi.list(Zoi.string()),
                    description: "Allowed state transitions"
                  )
                  |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Creates a new machine with the given initial state and transitions."
    @spec new(String.t(), map()) :: t()
    def new(initial_state, transitions) do
      %__MODULE__{
        status: initial_state,
        transitions: transitions
      }
    end

    @doc "Attempts to transition to a new state."
    @spec transition(t(), String.t()) :: {:ok, t()} | {:error, String.t()}
    def transition(%__MODULE__{status: current, transitions: transitions} = machine, new_status) do
      allowed = Map.get(transitions, current, [])

      if new_status in allowed do
        {:ok, %{machine | status: new_status}}
      else
        {:error, "invalid transition from #{current} to #{new_status}"}
      end
    end
  end

  @impl true
  def init(agent, ctx) do
    opts = ctx[:strategy_opts] || []
    initial_state = Keyword.get(opts, :initial_state, @default_initial_state)
    transitions = Keyword.get(opts, :transitions, @default_transitions)
    thread_enabled? = Keyword.get(opts, :thread?, false)

    machine = Machine.new(initial_state, transitions)

    agent =
      StratState.put(agent, %{
        machine: machine,
        module: __MODULE__,
        initial_state: initial_state,
        auto_transition: Keyword.get(opts, :auto_transition, true),
        pending_instructions: [],
        current_instruction: nil,
        deferred_directives: []
      })

    agent =
      if thread_enabled? or ThreadAgent.has_thread?(agent) do
        agent = ThreadAgent.ensure(agent)
        append_checkpoint(agent, :init, initial_state)
      else
        agent
      end

    {agent, []}
  end

  @impl true
  def cmd(
        %Agent{} = agent,
        [%Instruction{action: @instruction_result_action, params: result_payload}],
        ctx
      ) do
    handle_instruction_result(agent, result_payload, ctx)
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) when is_list(instructions) do
    state = StratState.get(agent, %{})
    opts = ctx[:strategy_opts] || []

    initial_state =
      Map.get(state, :initial_state, Keyword.get(opts, :initial_state, @default_initial_state))

    transitions = Keyword.get(opts, :transitions, @default_transitions)
    auto_transition = Map.get(state, :auto_transition, Keyword.get(opts, :auto_transition, true))
    thread_enabled? = Keyword.get(opts, :thread?, false)

    machine = Map.get(state, :machine) || Machine.new(initial_state, transitions)

    agent = maybe_ensure_thread(agent, thread_enabled?)

    case Machine.transition(machine, "processing") do
      {:ok, machine} ->
        agent = maybe_append_checkpoint(agent, :transition, "processing")

        strategy_state = %{
          state
          | machine: machine,
            initial_state: initial_state,
            auto_transition: auto_transition,
            pending_instructions: instructions,
            current_instruction: nil,
            deferred_directives: []
        }

        dispatch_next_instruction(agent, strategy_state)

      {:error, reason} ->
        error = Error.execution_error("FSM transition failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :fsm_transition}]}
    end
  end

  defp maybe_ensure_thread(agent, thread_enabled?) do
    if thread_enabled? or ThreadAgent.has_thread?(agent) do
      ThreadAgent.ensure(agent)
    else
      agent
    end
  end

  defp maybe_append_checkpoint(agent, event, fsm_state) do
    if ThreadAgent.has_thread?(agent) do
      append_checkpoint(agent, event, fsm_state)
    else
      agent
    end
  end

  defp append_checkpoint(agent, event, fsm_state) do
    entry = %{
      kind: :checkpoint,
      payload: %{event: event, fsm_state: fsm_state}
    }

    ThreadAgent.append(agent, entry)
  end

  defp dispatch_next_instruction(agent, state) do
    case Map.get(state, :pending_instructions, []) do
      [next_instruction | rest] ->
        agent = InstructionTracking.maybe_append_instruction_start(agent, next_instruction)

        directives = [
          Directive.run_instruction(next_instruction,
            result_action: @instruction_result_action,
            meta: %{strategy: __MODULE__}
          )
        ]

        state = %{state | pending_instructions: rest, current_instruction: next_instruction}
        agent = StratState.put(agent, state)
        {agent, directives}

      [] ->
        finalize_batch(agent, state)
    end
  end

  defp finalize_batch(agent, state) do
    machine =
      maybe_auto_transition(
        Map.fetch!(state, :machine),
        Map.get(state, :auto_transition, true),
        Map.get(state, :initial_state, @default_initial_state)
      )

    agent = maybe_append_checkpoint(agent, :transition, machine.status)
    directives = Map.get(state, :deferred_directives, [])

    state = %{
      state
      | machine: machine,
        pending_instructions: [],
        current_instruction: nil,
        deferred_directives: []
    }

    agent = StratState.put(agent, state)
    {agent, directives}
  end

  defp handle_instruction_result(agent, result_payload, ctx) when is_map(result_payload) do
    state = StratState.get(agent, %{})
    opts = ctx[:strategy_opts] || []

    initial_state =
      Map.get(state, :initial_state, Keyword.get(opts, :initial_state, @default_initial_state))

    transitions = Keyword.get(opts, :transitions, @default_transitions)
    auto_transition = Map.get(state, :auto_transition, Keyword.get(opts, :auto_transition, true))
    machine = Map.get(state, :machine) || Machine.new(initial_state, transitions)

    {agent, machine, new_directives, status} =
      apply_instruction_result(agent, machine, result_payload)

    agent =
      InstructionTracking.maybe_append_instruction_end(
        agent,
        Map.get(state, :current_instruction),
        status
      )

    deferred_directives = Map.get(state, :deferred_directives, []) ++ new_directives

    strategy_state = %{
      state
      | machine: machine,
        initial_state: initial_state,
        auto_transition: auto_transition,
        deferred_directives: deferred_directives
    }

    dispatch_next_instruction(agent, strategy_state)
  end

  defp handle_instruction_result(agent, _result_payload, _ctx) do
    error = Error.execution_error("Instruction result payload must be a map", %{})
    {agent, [%Directive.Error{error: error, context: :instruction_result}]}
  end

  defp maybe_auto_transition(machine, false, _initial_state), do: machine

  defp maybe_auto_transition(machine, true, initial_state) do
    case Machine.transition(machine, initial_state) do
      {:ok, m} -> m
      {:error, _} -> machine
    end
  end

  defp apply_instruction_result(agent, machine, %{status: :ok, result: result, effects: effects})
       when is_map(result) do
    machine = %{machine | processed_count: machine.processed_count + 1, last_result: result}
    agent = StateOps.apply_result(agent, result)
    {agent, directives} = StateOps.apply_state_ops(agent, List.wrap(effects))
    {agent, machine, directives, :ok}
  end

  defp apply_instruction_result(agent, machine, %{status: :ok, result: result})
       when is_map(result) do
    machine = %{machine | processed_count: machine.processed_count + 1, last_result: result}
    {StateOps.apply_result(agent, result), machine, [], :ok}
  end

  defp apply_instruction_result(agent, machine, %{status: :error, reason: reason}) do
    machine = %{machine | error: reason}
    error = Error.execution_error("Instruction failed", %{reason: reason})
    {agent, machine, [%Directive.Error{error: error, context: :instruction}], :error}
  end

  defp apply_instruction_result(agent, machine, payload) do
    machine = %{machine | error: payload}
    error = Error.execution_error("Invalid instruction execution payload", %{payload: payload})
    {agent, machine, [%Directive.Error{error: error, context: :instruction}], :error}
  end

  @impl true
  def snapshot(agent, _ctx) do
    state = StratState.get(agent, %{})
    machine = Map.get(state, :machine, %{})
    status = parse_status(Map.get(machine, :status, "idle"))

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: Map.get(machine, :last_result),
      details: %{
        processed_count: Map.get(machine, :processed_count, 0),
        error: Map.get(machine, :error),
        fsm_state: Map.get(machine, :status)
      }
    }
  end

  defp parse_status("idle"), do: :idle
  defp parse_status("processing"), do: :running
  defp parse_status("completed"), do: :success
  defp parse_status("failed"), do: :failure
  defp parse_status(_), do: :idle
end
