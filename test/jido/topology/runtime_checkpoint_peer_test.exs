defmodule Jido.Topology.RuntimeCheckpointPeerTest do
  use JidoTest.PeerCase, async: false

  alias Jido.{Signal, Topology}
  alias Jido.Topology.Runtime
  alias JidoTest.AgentFixtures.CounterAgent

  test "remote member checkpoints survive Runtime failure and clear on clean stop", c do
    id = "runtime-checkpoint-#{System.unique_integer([:positive])}"

    topology =
      Topology.new!(
        name: "remote_checkpoint",
        agents: [%{key: :counter, module: CounterAgent, node: c.node_b}]
      )

    spec = {Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy}
    assert {:ok, root} = peer_call(c.peer_a, Supervisor, :start_child, [Jido.Supervisor, spec])
    assert {:ok, %{state: %{count: 7}}} = call(c, id, 7)
    assert true = peer_call(c.peer_a, Process, :exit, [root, :kill])

    peer_eventually(fn ->
      replacement = peer_call(c.peer_a, Runtime, :whereis_runtime, [c.jido, id])

      is_pid(replacement) and replacement != root and
        is_pid(peer_call(c.peer_a, Runtime, :controller, [c.jido, id])) and
        is_pid(peer_call(c.peer_a, Runtime, :lookup, [c.jido, id, :gateway]))
    end)

    assert :ok = peer_call(c.peer_a, Runtime, :await_ready, [c.jido, id])
    assert {:ok, %{state: %{count: 8}}} = call(c, id, 1)

    assert :ok =
             peer_call(c.peer_a, Supervisor, :terminate_child, [Jido.Supervisor, {Runtime, id}])

    assert {:ok, _} =
             peer_call(c.peer_a, Supervisor, :restart_child, [Jido.Supervisor, {Runtime, id}])

    assert {:ok, %{state: %{count: 1}}} = call(c, id, 1)

    assert :ok =
             peer_call(c.peer_a, Supervisor, :terminate_child, [Jido.Supervisor, {Runtime, id}])
  end

  defp call(c, id, count) do
    signal = Signal.new!("counter.add", %{by: count, label: "remote"}, source: "/test")
    peer_call(c.peer_a, Runtime, :call, [c.jido, id, :counter, signal])
  end
end
