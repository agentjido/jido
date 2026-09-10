defmodule Jido.Topology.SignalTest do
  use JidoTest.Case, async: true

  alias Jido.Topology.Signal

  alias Jido.Topology.Signal.{
    ComponentFailed,
    ComponentReady,
    OperationCompleted,
    OperationStarted,
    StatusChanged
  }

  @signals [
    OperationStarted,
    OperationCompleted,
    ComponentReady,
    ComponentFailed,
    StatusChanged
  ]

  test "lifecycle events are custom Signal modules" do
    assert Signal.types() == Enum.map(@signals, & &1.type())

    assert OperationStarted.type() == "jido.topology.lifecycle.operation.started"
    assert OperationCompleted.type() == "jido.topology.lifecycle.operation.completed"
    assert ComponentReady.type() == "jido.topology.lifecycle.component.ready"
    assert ComponentFailed.type() == "jido.topology.lifecycle.component.failed"
    assert StatusChanged.type() == "jido.topology.lifecycle.status.changed"
  end

  test "custom modules validate their lifecycle data" do
    assert %Jido.Signal{source: "/jido/topology"} =
             OperationStarted.new!(%{
               topology_id: "system",
               operation_id: "operation",
               operation: "activate"
             })

    assert %Jido.Signal{data: %{previous: nil, current: "ready"}} =
             StatusChanged.new!(%{
               topology_id: "system",
               operation_id: "operation",
               previous: nil,
               current: "ready"
             })

    assert {:error, _errors} = ComponentReady.new(%{topology_id: "system"})

    assert {:error, _errors} =
             OperationStarted.new(%{
               topology_id: "system",
               operation_id: "operation",
               operation: "rebalance"
             })
  end
end
