Code.require_file("example.ex", __DIR__)

defmodule Jido.Examples.Statechart.ApprovalTest do
  use Jido.Test.Case, async: false

  alias Jido.{AgentServer, Signal, Statechart}
  alias Jido.Examples.Statechart.Approval

  @moduletag :integration

  test "each order starts in pending and keeps its final decision", %{jido: jido} do
    for decision <- ["approved", "rejected"] do
      id = unique_id("order")
      assert {:ok, order} = Statechart.spawn(jido, Approval, id: id)
      assert %{state: "pending", status: :active} = Statechart.session(order)

      assert {:ok, %{status: :committed}} = AgentServer.call(order, event_signal(decision))
      assert %{state: ^decision, status: :completed} = Statechart.session(order)

      assert {:ok, %{status: :committed}} = AgentServer.call(order, event_signal("approved"))
      assert %{state: ^decision, status: :completed} = Statechart.session(order)

      assert :ok = Jido.stop_agent(jido, order)
      refute Process.alive?(order)
    end
  end

  defp event_signal(decision),
    do: Signal.new!("examples.statechart.approval.#{decision}", %{}, source: "/examples/statechart/approval")
end
