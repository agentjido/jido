Code.require_file("sink.ex", __DIR__)
Code.require_file("worker.ex", __DIR__)
Code.require_file("direct_connections.ex", __DIR__)
Code.require_file("../support/runtime.ex", __DIR__)

defmodule Jido.Examples.Topology.DirectConnectionsTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Topology.DirectConnections, as: Example
  alias Jido.Examples.Topology.Runtime

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"topology_connections_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "outputs travel root to worker to sink to root in separate commits", %{instance: instance} do
    assert {:ok, root} = Runtime.start(instance, Example, 3)

    signal =
      Jido.Signal.new!("examples.topology.pipeline.request", %{value: 3},
        source: "/examples/topology/direct_connections"
      )

    assert {:ok, %{status: :committed}} = AgentServer.call(root, signal)
    assert AgentServer.snapshot(root).agent.state.completed == 0
    assert Runtime.eventually(fn -> AgentServer.snapshot(root).agent.state.completed == 6 end)
    assert AgentServer.snapshot(root).agent_revision == 2
    assert Enum.all?(Runtime.members(instance, root), &(AgentServer.snapshot(&1).agent_revision == 1))

    assert {:ok, checks} =
             Jido.Agent.Topology.checks(
               Example.definition(),
               [],
               &Jido.Agent.Validation.resolve/2
             )

    assert Enum.all?(checks, &(&1.status == :unchecked))
    assert :ok = Runtime.stop(instance, root)
  end

  test "connections are validated as part of the complete definition" do
    definition = Example.definition()
    assert length(definition.topology.connections) == 2

    invalid =
      put_in(definition.topology.connections, [
        %{
          path: "examples.topology.pipeline.receipt",
          from: %{kind: :agent, name: :sink},
          to: %{kind: :agent, name: :worker},
          delivery: :single
        }
      ])

    assert {:error, %{code: :unaccepted_type}} = invalid |> Map.from_struct() |> Jido.Agent.define()
  end
end
