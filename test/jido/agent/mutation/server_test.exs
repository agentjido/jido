defmodule Jido.Agent.MutationServerTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Directive, as: D
  alias Jido.AgentServer, as: Server
  alias Jido.Persistence
  alias JidoTest.AgentEvolutionFixtures, as: F
  import JidoTest.Eventually

  test "a committed route mutation changes the next Turn and invalid edits preserve it", %{
    jido: jido
  } do
    initial = %{F.agent() | id: unique_id("mutation")}
    assert {:ok, server} = Jido.start_agent(jido, initial)
    assert :ok = Server.await_ready(server)
    edits = [D.route_add("next", F.Work), D.route_remove("run")]
    assert {:ok, candidate, ^edits} = Server.call(server, F.signal(edits))
    assert Server.agent(server) === candidate
    assert Enum.map(candidate.routes, & &1.path) == ["next"]
    assert {:error, _} = Server.call(server, F.signal([]))
    input = Jido.Signal.new!("next", %{directives: [D.route_remove("absent")]}, source: "/test")
    assert {:error, _} = Server.call(server, input)
    assert Server.agent(server) === candidate
    assert Server.status(server).state_version == 1
  end

  test "durable and local recovery retain the accepted routes and Plugin state", %{jido: jido} do
    initial = %{F.agent() | id: unique_id("recovery")}
    store = {Persistence.ETS, table: __MODULE__}
    assert {:ok, server} = Jido.start_agent(jido, initial, persistence: store)
    assert :ok = Server.await_ready(server)
    edits = [D.route_add("next", F.Work), D.route_remove("run"), D.plugin_add(F.Counter)]
    assert {:ok, candidate, ^edits} = Server.call(server, F.signal(edits))
    assert :ok = Server.await_ready(server)

    assert {:ok, ^candidate, 1} =
             Persistence.load_agent_with_revision(store, initial.module, initial.id,
               instance: jido
             )

    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}

    recovered =
      eventually(fn ->
        pid = Jido.whereis_agent(jido, initial.id)
        if is_pid(pid) and pid != server, do: pid
      end)

    assert :ok = Server.await_ready(recovered)
    assert Server.agent(recovered) === candidate
    assert Server.status(recovered).state_version == 1
    assert :ok = Jido.stop_agent(jido, recovered)

    assert {:ok, restored} =
             Jido.start_agent(jido, initial, persistence: store, persistence_mode: :restore)

    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored) === candidate
    assert Server.status(restored).state_version == 1
  end

  test "topology activation follows the accepted candidate", %{jido: jido} do
    initial = %{F.agent() | id: unique_id("topology")}
    assert {:ok, server} = Jido.start_agent(jido, initial)
    assert :ok = Server.await_ready(server)
    assert {:ok, candidate, _} = Server.call(server, F.signal([D.agent_add(:worker, F.Worker)]))
    assert :ok = Server.await_ready(server)
    assert Server.agent(server) === candidate
    assert Server.status(server).state_version == 1
    assert map_size(Server.children(server)) == 1
  end
end
