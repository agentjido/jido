Code.require_file("topology_handoff.ex", __DIR__)

defmodule Jido.Examples.Durable.TopologyHandoffTest do
  use Jido.Test.Case, async: false

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.TopologyHandoff, as: Example

  test "a sender recovers committed work and its responder accepts it once", c do
    c = restart_jido!(c, {Jido.Persistence.File, path: c.tmp_dir})
    {:ok, address} = Jido.agent_address(c.jido, "team")
    assert {:ok, ^address} = Jido.create_agent(c.jido, address, Example)
    assert {:ok, root} = Jido.activate_agent(c.jido, address)
    member = %{address | id: "team/$topology/responder/1/initial"}
    assert {:ok, responder} = Jido.resolve_agent(c.jido, member)

    assert {:ok, _status} = Server.quiesce(responder)
    assert {:ok, %{status: :committed}} = Jido.call(c.jido, address, Example.assign_signal!(%{}))
    assert %{topology_handoffs: %{pending: 1}} = Server.status(root)
    assert Server.snapshot(responder).agent.state.assigned == 0

    assert :ok = Jido.stop_agent(c.jido, root)
    assert {:ok, restored} = Jido.activate_agent(c.jido, address)

    eventually(fn -> match?(%{topology_handoffs: %{pending: 0}}, Server.status(restored)) end)
    assert {:ok, new_responder} = Jido.resolve_agent(c.jido, member)
    assert {:ok, _status} = Server.quiesce(new_responder)
    assert Server.snapshot(new_responder).agent.state.assigned == 1
  end
end
