defmodule JidoActionCompatTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Instruction
  alias Jido.Observe.Config, as: ObserveConfig

  @jido_action_v3 Code.ensure_loaded?(Jido.Action) and
                    function_exported?(Jido.Action, :api_version, 0) and
                    apply(Jido.Action, :api_version, []) == 3

  defmodule IncrementAction do
    use Jido.Action,
      name: "compat_increment",
      description: "Increment compatibility state",
      category: "compatibility",
      tags: ["jido-v2"],
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
      state = %{agent.state | command: instruction.action, params: instruction.params}
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

  test "compiles for the selected dependency major" do
    version = if @jido_action_v3, do: 3, else: 2
    assert version in [2, 3]

    if expected = System.get_env("JIDO_ACTION_MAJOR") do
      assert version == String.to_integer(expected)
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

  test "uses the dependency Instruction API without a core adapter" do
    assert {:ok, instruction} =
             Instruction.new(
               action: IncrementAction,
               params: %{amount: 3},
               context: %{state: %{count: 4}},
               opts: [timeout: 1_000]
             )

    assert instruction.action == IncrementAction
    assert instruction.opts[:timeout] == 1_000

    exec_opts = ObserveConfig.action_exec_opts(nil, instruction.opts)
    assert {:ok, %{count: 7}} = Jido.Exec.run(%{instruction | opts: exec_opts})

    if @jido_action_v3 do
      assert Map.get(instruction, :target) == IncrementAction
      assert apply(Jido.Exec, :supported_options, [instruction]) == [:timeout, :jido]
    end
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
    instruction = Instruction.new!(action: :fsm_instruction_result)
    instruction = %{instruction | params: :invalid}
    agent = FSMAgent.new()
    ctx = %{agent_module: FSMAgent, strategy_opts: []}

    assert {^agent, [%Directive.Error{context: :instruction_result}]} =
             Jido.Agent.Strategy.FSM.cmd(agent, [instruction], ctx)
  end

  test "uses restored Action discovery metadata" do
    metadata = IncrementAction.__action_metadata__()
    metadata = if is_list(metadata), do: Map.new(metadata), else: metadata

    assert metadata.name == "compat_increment"
    assert metadata.description == "Increment compatibility state"
    assert metadata.category == "compatibility"
    assert metadata.tags == ["jido-v2"]
  end
end
