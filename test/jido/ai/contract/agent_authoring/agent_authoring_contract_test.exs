defmodule Jido.AI.Contract.AgentAuthoringTest do
  use Covenant.Case, component: "jido_ai.agent_authoring", async: true

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AITest.Tools.Add

  defmodule DefaultIdentityAgent do
    use Jido.AI.Agent, name: "jido_ai_default_identity"

    ai do
      reasoning Jido.AI.Reasoning.ReAct
    end
  end

  defmodule ContractAgent do
    use Jido.AI.Agent,
      name: "jido_ai_contract_authoring",
      id: "jido.ai/contracts/authoring"

    ai do
      reasoning Jido.AI.Reasoning.ReAct

      tools do
        action Jido.AITest.Tools.Add
      end
    end
  end

  @tag obligation: "jido_ai.agent_authoring.I1"
  test "the core Agent default ID also defines the AI signal source" do
    id = Atom.to_string(DefaultIdentityAgent)

    assert DefaultIdentityAgent.__jido_authoring__().id == id
    assert DefaultIdentityAgent.definition().signal_source == "/" <> id
  end

  @tag obligation: ["jido_ai.agent_authoring.I1", "jido_ai.agent_authoring.I3"]
  test "one AI declaration creates one direct reasoning route" do
    assert ContractAgent.reasoning() == ReAct

    assert [
             %{
               path: "jido.ai.request",
               handler: %{kind: :flow, target: ReAct}
             }
           ] = ContractAgent.definition().routes

    assert ContractAgent.route_executable!("jido.ai.request") == ReAct

    assert [
             %{
               data: %{reasoning: ReAct, tools: [Add]}
             }
           ] = ContractAgent.definition().plugins
  end

  @tag obligation: "jido_ai.agent_authoring.I2"
  test "a repeated reasoning declaration is rejected" do
    module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.AI.Agent, name: "invalid_contract_agent"

      ai do
        reasoning Jido.AI.Reasoning.ReAct
        reasoning Jido.AI.Reasoning.ChainOfThought
      end
    end
    """

    assert_raise CompileError, ~r/ai requires exactly one reasoning declaration/, fn ->
      Code.compile_string(source)
    end
  end

  @tag obligation: "jido_ai.agent_authoring.I4"
  test "inspection and preflight expose portable graph data" do
    assert %{
             agent: ContractAgent,
             reasoning: ReAct,
             tools: [Add],
             flow: %Jido.Flow{}
           } = ContractAgent.explain()

    assert {:ok,
            %{
              agent: ContractAgent,
              reasoning: ReAct,
              params: %{input: "Inspect the graph."},
              tools: [Add],
              flow: %Jido.Flow{},
              workflow: %Runic.Workflow{}
            }} = ContractAgent.preflight(%{input: "Inspect the graph."})

    assert {:error, _reason} = ContractAgent.preflight(%{})
  end
end
