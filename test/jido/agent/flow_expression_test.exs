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

  test "Flow DSL and data definition share Jido.Expr through Agent Codec and execution", %{
    jido: jido
  } do
    import Jido.Expr, only: [expr: 1]

    amount = Ref.input(:amount)
    count = Ref.context([:agent_state, :count])
    added = Ref.result("amount", :amount)

    flow =
      Jido.Flow.new(
        name: "expression_add",
        schema: Add.schema(),
        components: [
          Jido.Flow.Step.new!(
            name: "amount",
            action: Amount,
            params: %{amount: expr(min(^amount, 5))}
          )
        ],
        output: %{count: expr(^count + ^added)}
      )

    assert {:ok, flow} = flow
    assert flow == Add.flow()
    assert %Jido.Expr{} = flow.output.count

    for target <- [Add, flow] do
      definition =
        Jido.Agent.new!(%{
          schema: Counter.domain_schema(),
          name: "expression_counter",
          routes: [{"counter.add", target, defaults: %{amount: 2}}]
        })

      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      instance = Agent.instantiate!(definition, state: %{count: 10})

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

      {:ok, server} = Jido.start_agent(jido, instance)

      {:ok, route_signal_1} = Counter.add_signal(%{amount: 9})

      assert {:ok, %{state: %{count: 15}}} =
               Jido.AgentServer.call(server, route_signal_1, [])

      assert Jido.AgentServer.snapshot(server).state_version == 1
    end
  end

  test "expression failures preserve committed Agent state", %{jido: jido} do
    bad_flow = %{Add.flow() | output: %{count: Jido.Expr.new!(:divide, [1, 0])}}

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

    {:ok, server} = Jido.start_agent(jido, instance)
    before = Jido.AgentServer.snapshot(server)

    {:ok, route_signal_2} = Counter.add_signal(%{})

    assert {:error, _error} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert Jido.AgentServer.snapshot(server) == before
  end
end
