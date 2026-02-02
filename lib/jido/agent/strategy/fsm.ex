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

  The strategy automatically transitions through states as instructions execute.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.StateOps
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
        auto_transition: Keyword.get(opts, :auto_transition, true)
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
        {agent, machine, directives} = process_instructions(agent, machine, instructions)

        machine = maybe_auto_transition(machine, auto_transition, initial_state)
        agent = maybe_append_checkpoint(agent, :transition, machine.status)

        agent = StratState.put(agent, %{state | machine: machine})
        {agent, directives}

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

  defp process_instructions(agent, machine, instructions) do
    {final_agent, final_machine, reversed_directives} =
      Enum.reduce(instructions, {agent, machine, []}, fn instruction,
                                                         {acc_agent, acc_machine, acc_directives} ->
        {new_agent, new_machine, new_directives} =
          run_instruction_with_tracking(acc_agent, acc_machine, instruction)

        {new_agent, new_machine, Enum.reverse(new_directives) ++ acc_directives}
      end)

    {final_agent, final_machine, Enum.reverse(reversed_directives)}
  end

  defp maybe_auto_transition(machine, false, _initial_state), do: machine

  defp maybe_auto_transition(machine, true, initial_state) do
    case Machine.transition(machine, initial_state) do
      {:ok, m} -> m
      {:error, _} -> machine
    end
  end

  defp run_instruction_with_tracking(agent, machine, %Instruction{} = instruction) do
    if ThreadAgent.has_thread?(agent) do
      agent = append_instruction_start(agent, instruction)
      {agent, machine, directives, status} = run_instruction(agent, machine, instruction)
      agent = append_instruction_end(agent, instruction, status)
      {agent, machine, directives}
    else
      {agent, machine, directives, _status} = run_instruction(agent, machine, instruction)
      {agent, machine, directives}
    end
  end

  defp run_instruction(agent, machine, %Instruction{} = instruction) do
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        machine = %{machine | processed_count: machine.processed_count + 1, last_result: result}
        {StateOps.apply_result(agent, result), machine, [], :ok}

      {:ok, result, effects} when is_map(result) ->
        machine = %{machine | processed_count: machine.processed_count + 1, last_result: result}
        agent = StateOps.apply_result(agent, result)
        {agent, directives} = StateOps.apply_state_ops(agent, List.wrap(effects))
        {agent, machine, directives, :ok}

      {:error, reason} ->
        machine = %{machine | error: reason}
        error = Error.execution_error("Instruction failed", %{reason: reason})
        {agent, machine, [%Directive.Error{error: error, context: :instruction}], :error}
    end
  end

  defp append_instruction_start(agent, %Instruction{} = instruction) do
    entry = %{
      kind: :instruction_start,
      payload: instruction_payload(instruction)
    }

    ThreadAgent.append(agent, entry)
  end

  defp append_instruction_end(agent, %Instruction{} = instruction, status) do
    entry = %{
      kind: :instruction_end,
      payload: Map.put(instruction_payload(instruction), :status, status)
    }

    ThreadAgent.append(agent, entry)
  end

  defp instruction_payload(%Instruction{} = instruction) do
    payload = %{action: instruction.action}

    payload =
      if is_map(instruction.params) and map_size(instruction.params) > 0 do
        Map.put(payload, :param_keys, Map.keys(instruction.params))
      else
        payload
      end

    if instruction.id do
      Map.put(payload, :instruction_id, instruction.id)
    else
      payload
    end
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
