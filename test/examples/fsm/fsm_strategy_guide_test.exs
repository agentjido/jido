defmodule JidoExampleTest.FSMStrategyGuideTest do
  @moduledoc """
  Example test covering the public FSM strategy guide workflow.

  This test shows:
  - Runtime-driven execution via `AgentServer.call/3`
  - FSM execution-state transitions through `"processing"`
  - Domain workflow state stored in regular agent state

  Run with: mix test test/examples/fsm/fsm_strategy_guide_test.exs --include example
  """
  use JidoTest.Case, async: true

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.AgentServer

  defmodule ConfirmOrder do
    @moduledoc false
    use Jido.Action,
      name: "confirm_order",
      schema: []

    def run(_params, context) do
      case context.state[:order_status] do
        :pending -> {:ok, %{order_status: :confirmed}}
        other -> {:error, "cannot confirm order from #{inspect(other)}"}
      end
    end
  end

  defmodule ShipOrder do
    @moduledoc false
    use Jido.Action,
      name: "ship_order",
      schema: [
        carrier: [type: :string, default: "Standard Shipping"]
      ]

    def run(%{carrier: carrier}, context) do
      case context.state[:order_status] do
        :confirmed ->
          {:ok, %{order_status: :shipped, shipped_at: DateTime.utc_now(), shipped_via: carrier}}

        other ->
          {:error, "cannot ship order from #{inspect(other)}"}
      end
    end
  end

  defmodule DeliverOrder do
    @moduledoc false
    use Jido.Action,
      name: "deliver_order",
      schema: []

    def run(_params, context) do
      case context.state[:order_status] do
        :shipped -> {:ok, %{order_status: :delivered, delivered_at: DateTime.utc_now()}}
        other -> {:error, "cannot deliver order from #{inspect(other)}"}
      end
    end
  end

  defmodule OrderAgent do
    @moduledoc false
    use Jido.Agent,
      name: "guide_order_agent",
      description: "Order workflow agent used in the FSM strategy guide",
      schema: [
        order_id: [type: :string],
        customer: [type: :string],
        items: [type: {:list, :map}, default: []],
        total: [type: :float, default: 0.0],
        order_status: [type: :atom, default: :pending],
        shipped_via: [type: :string, default: nil],
        shipped_at: [type: :any, default: nil],
        delivered_at: [type: :any, default: nil]
      ],
      signal_routes: [
        {"order.confirm", ConfirmOrder},
        {"order.ship", ShipOrder},
        {"order.deliver", DeliverOrder}
      ],
      strategy:
        {Jido.Agent.Strategy.FSM,
         initial_state: "ready",
         transitions: %{
           "ready" => ["processing"],
           "processing" => ["ready"]
         },
         auto_transition: true}
  end

  defp wait_for_idle!(pid) do
    eventually_state(
      pid,
      fn state ->
        state.agent_module.strategy_snapshot(state.agent).status == :idle
      end,
      timeout: 1_000
    )

    {:ok, state} = AgentServer.state(pid)
    state.agent
  end

  describe "FSM strategy guide example" do
    test "runtime execution updates order state while FSM returns to ready", context do
      pid =
        start_server(context, OrderAgent,
          initial_state: %{
            order_id: "ORD-12345",
            customer: "Alice",
            items: [%{sku: "WIDGET-A", qty: 2}],
            total: 49.99,
            order_status: :pending
          }
        )

      {:ok, _agent} = AgentServer.call(pid, signal("order.confirm"))
      agent = wait_for_idle!(pid)
      snap = OrderAgent.strategy_snapshot(agent)

      assert agent.state.order_status == :confirmed
      assert snap.details.fsm_state == "ready"
      assert snap.details.processed_count == 1

      {:ok, _agent} =
        AgentServer.call(pid, signal("order.ship", %{carrier: "FedEx Express"}))

      agent = wait_for_idle!(pid)
      snap = OrderAgent.strategy_snapshot(agent)

      assert agent.state.order_status == :shipped
      assert agent.state.shipped_via == "FedEx Express"
      assert agent.state.shipped_at != nil
      assert snap.details.fsm_state == "ready"
      assert snap.details.processed_count == 2

      {:ok, _agent} = AgentServer.call(pid, signal("order.deliver"))
      agent = wait_for_idle!(pid)
      snap = OrderAgent.strategy_snapshot(agent)

      assert agent.state.order_status == :delivered
      assert agent.state.delivered_at != nil
      assert snap.details.fsm_state == "ready"
      assert snap.details.processed_count == 3
    end
  end
end
