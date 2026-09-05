defmodule JidoTest.Examples.HandoffTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.Handoff, as: Example
  alias Jido.AgentServer, as: Server

  setup %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Example)
    {:ok, _} = Example.command(server, "boot")
    eventually(fn -> Enum.sort(state(server).alive) == ["billing", "general"] end)
    %{server: server}
  end

  test "acknowledgement transfers authority and late or duplicate results cannot replace it", c do
    old = child(c.server, "general")
    billing = child(c.server, "billing")
    assert {:ok, _} = Example.command(c.server, "transfer", %{owner: "billing"})
    eventually(fn -> state(billing).generation == 1 end)
    assert state(c.server).owner == "general"
    assert {:ok, _} = Example.Worker.acknowledge(billing)
    eventually(fn -> state(c.server).owner == "billing" end)
    assert {:ok, _} = Example.Worker.acknowledge(billing)
    assert {:ok, _} = Example.Worker.complete(old, "late general answer")
    assert {:ok, _} = Example.Worker.complete(billing, "billing answer")
    eventually(fn -> state(c.server).result == "billing answer" end)
    assert {:ok, _} = Example.Worker.complete(billing, "duplicate replacement")
    # Synchronous replay also establishes a barrier after the worker's duplicate.
    assert {:ok, agent} =
             Example.command(c.server, "result", %{
               request: "case-1",
               owner: "billing",
               generation: 1,
               result: "another"
             })

    assert agent.state.result == "billing answer"
  end

  test "an unavailable recipient leaves the old owner and the transfer can be aborted", c do
    assert {:ok, agent} = Example.command(c.server, "transfer", %{owner: "missing"})
    assert agent.state.owner == "general"
    assert {:ok, agent} = Example.command(c.server, "abort")
    assert agent.state.pending == nil
    assert agent.state.owner == "general"
    assert {:ok, _} = Example.Worker.complete(child(c.server, "general"), "handled locally")
    eventually(fn -> state(c.server).result == "handled locally" end)
  end

  test "a recipient crash clears the offer and reconciliation uses a new generation", c do
    billing = child(c.server, "billing")
    assert {:ok, _} = Example.command(c.server, "transfer", %{owner: "billing"})
    eventually(fn -> state(billing).generation == 1 end)
    ref = Process.monitor(billing)
    Process.exit(billing, :kill)
    assert_receive {:DOWN, ^ref, :process, ^billing, _}, 1_000

    eventually(fn ->
      state(c.server).pending == nil and "billing" not in state(c.server).alive
    end)

    assert {:ok, _} = Example.command(c.server, "reconcile")
    eventually(fn -> "billing" in state(c.server).alive end)
    replacement = child(c.server, "billing")
    assert replacement != billing
    assert {:ok, _} = Example.command(c.server, "transfer", %{owner: "billing"})
    eventually(fn -> state(replacement).generation == 2 end)

    assert {:ok, agent} =
             Example.command(c.server, "ack", %{
               request: "case-1",
               owner: "billing",
               generation: 1
             })

    assert agent.state.owner == "general"
    assert {:ok, _} = Example.Worker.acknowledge(replacement)
    eventually(fn -> state(c.server).generation == 2 end)
    assert {:ok, _} = Example.Worker.complete(replacement, "recovered")
    eventually(fn -> state(c.server).result == "recovered" end)

    children =
      Enum.map(Server.children(c.server), fn {_, info} ->
        {info.pid, Process.monitor(info.pid)}
      end)

    assert :ok = Server.stop(c.server)

    for {pid, monitor} <- children,
        do: assert_receive({:DOWN, ^monitor, :process, ^pid, _}, 1_000)
  end

  defp state(server), do: Server.snapshot(server).agent.state
  defp child(server, tag), do: Server.children(server)[tag].pid
end
