defmodule Jido.Agent.FlowExpressionTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Flow.Ref

  defmodule Amount do
    use Jido.Action, name: "expression_amount", schema: Zoi.object(%{amount: Zoi.integer()})
    def run(input, _context), do: {:ok, input}
  end

  defmodule Add do
    use Jido.Flow, name: "expression_add", schema: Zoi.object(%{amount: Zoi.integer()})

    flow do
      step "amount", action: Amount, params: %{amount: min(input(:amount), 5)}
      output %{count: context([:agent_state, :count]) + result("amount", :amount)}
    end
  end

  defmodule Counter do
    use Jido.Agent, name: "expression_counter"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/expression"

      route "counter.add", Add, as: :add do
        defaults %{amount: 2}
      end
    end
  end

  test "Flow DSL and data definition share Jido.Expr through Agent Codec and direct execution" do
    import Jido.Expr, only: [expr: 1]

    amount = Ref.input(:amount)
    count = Ref.context([:agent_state, :count])
    added = Ref.result("amount", :amount)

    flow =
      Jido.Flow.new(%{
        name: "expression_add",
        schema: Add.schema(),
        components: [
          %{
            kind: :step,
            name: "amount",
            action: Amount,
            params: %{amount: expr(min(^amount, 5))}
          }
        ],
        output: %{count: expr(^count + ^added)}
      })

    assert {:ok, flow} = flow
    assert flow == Add.flow()
    assert %Jido.Expr{} = flow.output.count
    assert {:ok, %Runic.Workflow{}} = Jido.Exec.compile(flow)

    assert {:ok, flow_document, flow_registry} = Jido.Flow.Codec.encode(flow)

    assert {:ok, ^flow} =
             Jido.Flow.Codec.decode(JSON.decode!(JSON.encode!(flow_document)), flow_registry)

    for target <- [Add, flow] do
      definition =
        Jido.Agent.new!(%{
          schema: Counter.domain_schema(),
          name: "expression_counter",
          routes: [{"counter.add", target, defaults: %{amount: 2}}]
        })

      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, decoded} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      assert decoded == definition
      instance = Agent.instantiate!(decoded, state: %{count: 10})

      {:ok, command_signal_1} = Counter.add_signal(%{})

      assert {:ok, %{state: %{count: 12}}, []} =
               Agent.cmd(
                 instance,
                 command_signal_1
               )

      {:ok, command_signal_2} = Counter.add_signal(%{amount: 9})

      assert {:ok, %{state: %{count: 15}}, []} =
               Agent.cmd(
                 instance,
                 command_signal_2
               )
    end
  end

  test "Flow expressions commit through AgentServer", %{jido: jido} do
    for target <- [Add, Add.flow()] do
      definition =
        Agent.new!(%{
          schema: Counter.domain_schema(),
          name: "expression_counter",
          routes: [{"counter.add", target, defaults: %{amount: 2}}]
        })

      instance = Agent.instantiate!(definition, state: %{count: 10})
      {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, instance)

      {:ok, route_signal_1} = Counter.add_signal(%{amount: 9})

      assert {:ok, %{state: %{count: 15}}, _} =
               Jido.AgentServer.call(server, route_signal_1, [])

      assert Jido.AgentServer.status(server).state_version == 1
    end
  end

  test "expression failures preserve the direct Agent state" do
    bad_flow = %{Add.flow() | output: %{count: Jido.Expr.new!(:/, [1, 0])}}

    definition =
      Agent.new!(
        name: "invalid_expression",
        schema: Counter.domain_schema(),
        routes: [{"counter.add", {bad_flow, %{amount: 2}}}]
      )

    instance = Agent.instantiate!(definition, state: %{count: 10})

    {:ok, command_signal_3} = Counter.add_signal(%{})

    assert {:error, error} =
             Agent.cmd(instance, command_signal_3)

    assert is_exception(error)
    assert instance.state == %{count: 10}
  end

  test "expression failures preserve committed AgentServer state", %{jido: jido} do
    bad_flow = %{Add.flow() | output: %{count: Jido.Expr.new!(:/, [1, 0])}}

    definition =
      Agent.new!(
        name: "invalid_expression",
        schema: Counter.domain_schema(),
        routes: [{"counter.add", {bad_flow, %{amount: 2}}}]
      )

    instance = Agent.instantiate!(definition, state: %{count: 10})
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, instance)
    before = JidoTest.AgentServerAssertions.committed(server)

    {:ok, route_signal_2} = Counter.add_signal(%{})

    assert {:error, _error} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert JidoTest.AgentServerAssertions.committed(server) == before
  end
end
