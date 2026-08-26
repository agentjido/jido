defmodule JidoActionCompatTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Instruction, as: AgentInstruction

  defmodule IncrementAction do
    use Jido.Action,
      name: "compat_increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    @impl true
    def run(%{amount: amount}, context) do
      {:ok, %{count: Map.get(context.state, :count, 0) + amount}}
    end
  end

  defmodule DirectAgent do
    use Jido.Agent,
      name: "compat_direct_agent",
      schema: [count: [type: :integer, default: 0]]
  end

  defmodule CaptureStrategy do
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, [instruction], _ctx) do
      state = %{
        agent.state
        | command: AgentInstruction.action(instruction),
          params: instruction.params
      }

      {%{agent | state: state}, []}
    end
  end

  defmodule ModuleCommand do
  end

  defmodule CommandAgent do
    use Jido.Agent,
      name: "compat_command_agent",
      strategy: CaptureStrategy,
      schema: [command: [type: :any, default: nil], params: [type: :map, default: %{}]]
  end

  defmodule FSMAgent do
    use Jido.Agent,
      name: "compat_fsm_agent",
      strategy: Jido.Agent.Strategy.FSM,
      schema: []
  end

  defmodule JsonSchemaAgent do
    use Jido.Agent,
      name: "compat_json_schema_agent",
      schema: %{
        "type" => "object",
        "properties" => %{"count" => %{"type" => "integer"}}
      }
  end

  if Jido.ActionCompat.v3?() do
    defmodule BareExecutable do
      @behaviour Jido.Executable

      @impl true
      def __jido_executable__, do: Jido.Executable.action(__MODULE__)

      def run(params, _context), do: {:ok, params}
      def validate_params(params), do: {:ok, params}
      def validate_output(output), do: {:ok, output}
    end
  end

  test "compiles for the selected dependency major" do
    assert AgentInstruction.jido_action_version() in [2, 3]

    if expected = System.get_env("JIDO_ACTION_MAJOR") do
      assert AgentInstruction.jido_action_version() == String.to_integer(expected)
    end
  end

  test "runs an Action through the Direct strategy" do
    agent = DirectAgent.new()

    assert {agent, []} =
             DirectAgent.cmd(agent, {IncrementAction, %{amount: 2}},
               timeout: 1_000,
               max_retries: 0
             )

    assert agent.state.count == 2
  end

  test "builds and reads a dependency-compatible Instruction" do
    assert {:ok, instruction} =
             AgentInstruction.new(IncrementAction, %{amount: 3}, %{state: %{count: 4}},
               timeout: 1_000
             )

    assert AgentInstruction.action(instruction) == IncrementAction
    assert AgentInstruction.exec_opts(instruction)[:timeout] == 1_000
    assert {:ok, %{count: 7}} = AgentInstruction.run(instruction, timeout: 1_000)
  end

  test "preserves module-shaped strategy commands" do
    agent = CommandAgent.new()

    assert {agent, []} = CommandAgent.cmd(agent, {ModuleCommand, %{value: 1}})
    assert agent.state.command == ModuleCommand
    assert agent.state.params == %{value: 1}
  end

  test "keeps JSON Schema agent state as pass-through data" do
    agent = JsonSchemaAgent.new(state: %{count: "not validated by design"})

    assert {:ok, validated} = JsonSchemaAgent.validate(agent)
    assert validated.state.count == "not validated by design"
  end

  test "returns a directive for an invalid FSM result payload" do
    agent = FSMAgent.new()
    instruction = AgentInstruction.new!(:fsm_instruction_result)
    instruction = %{instruction | params: :invalid}
    ctx = %{agent_module: FSMAgent, strategy_opts: []}

    assert {^agent, [%Directive.Error{context: :instruction_result}]} =
             Jido.Agent.Strategy.FSM.cmd(agent, [instruction], ctx)
  end

  if Jido.ActionCompat.v3?() do
    test "uses fallback discovery metadata for a valid bare executable" do
      executable = JidoActionCompatTest.BareExecutable

      assert Jido.ActionCompat.action?(executable)
      assert %{name: name, description: nil} = Jido.ActionCompat.action_metadata(executable)
      assert name == Atom.to_string(executable)
    end
  end
end
