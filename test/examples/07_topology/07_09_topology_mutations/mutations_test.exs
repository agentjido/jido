defmodule JidoTest.Examples.Topology.MutationsTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.AgentTopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Mutations, Cell}

  test "add, grow, shrink, and remove preserve unchanged members", %{jido: jido} do
    server = start_topology(jido, Mutations)
    [observer] = labeled(server, "observer")
    assert {:ok, signal} = Mutations.workers_add_signal(%{count: 2})
    assert {:ok, _, [_]} = Server.call(server, signal)
    assert :ok = Server.await_ready(server)
    workers = labeled(server, "worker")
    assert length(workers) == 2

    for worker <- workers do
      assert {:ok, work} = Cell.work_signal(%{value: 7})
      assert {:ok, _, []} = Server.call(worker, work)
    end

    assert {:ok, grow} = Mutations.workers_resize_signal(%{count: 3})
    assert {:ok, _, [_]} = Server.call(server, grow)
    assert :ok = Server.await_ready(server)
    grown = labeled(server, "worker")
    assert length(grown) == 3
    assert workers -- grown == []
    assert Enum.all?(workers, &(Server.agent(&1).state.total == 7))
    [added] = grown -- workers
    assert Server.agent(added).state.total == 0

    assert {:ok, shrink} = Mutations.workers_resize_signal(%{count: 1})
    assert {:ok, _, [_]} = Server.call(server, shrink)
    assert :ok = Server.await_ready(server)
    [retained] = labeled(server, "worker")
    assert retained in workers
    assert Server.agent(retained).state.total == 7
    assert Enum.all?(grown -- [retained], &(not Process.alive?(&1)))
    assert labeled(server, "observer") == [observer]

    monitors = monitor_runtime(Server.activation(retained))
    assert {:ok, remove} = Mutations.workers_remove_signal()
    assert {:ok, _, [_]} = Server.call(server, remove)
    assert :ok = Server.await_ready(server)
    assert_down(monitors)
    assert members(server) == [observer]
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end

  test "replacement changes only the selected member", %{jido: jido} do
    server = start_topology(jido, Mutations)
    assert {:ok, add} = Mutations.workers_add_signal(%{count: 2})
    assert {:ok, _, [_]} = Server.call(server, add)
    assert :ok = Server.await_ready(server)
    workers = labeled(server, "worker") |> Enum.sort()
    [observer] = labeled(server, "observer")
    monitors = monitor_runtime(Server.activation(observer))

    assert {:ok, replace} = Mutations.observer_replace_signal()
    assert {:ok, _, [_]} = Server.call(server, replace)
    assert :ok = Server.await_ready(server)
    assert_down(monitors)
    [replacement] = labeled(server, "replacement")
    assert replacement != observer
    assert Enum.sort(labeled(server, "worker")) == workers
    stop_topology(server)
  end

  test "invalid mutations preserve the accepted Agent, revision, and runtimes", %{jido: jido} do
    server = start_topology(jido, Mutations)
    assert {:ok, add} = Mutations.workers_add_signal(%{count: 2})
    assert {:ok, _, [_]} = Server.call(server, add)
    assert :ok = Server.await_ready(server)
    before = Server.snapshot(server)
    children = Server.children(server)

    assert {:ok, invalid} = Mutations.workers_resize_signal(%{count: 0})
    assert {:error, _} = Server.call(server, invalid)
    assert {:error, _} = Server.call(server, add)
    assert Server.snapshot(server) == before
    assert Server.children(server) == children
    stop_topology(server)
  end

  test "a state-only change rebinds the count and reports its data Diff", %{jido: jido} do
    server = start_topology(jido, Mutations)
    assert {:ok, add} = Mutations.workers_add_signal(%{count: 2})
    assert {:ok, _, [_]} = Server.call(server, add)
    assert :ok = Server.await_ready(server)
    before = Server.agent(server)
    children = members(server)
    assert {:ok, bind} = Mutations.workers_bind_signal(%{count: 3})
    assert {:ok, accepted, []} = Server.call(server, bind)
    assert :ok = Server.await_ready(server)
    diff = Jido.Agent.Diff.between(before, accepted)
    assert Jido.Agent.Diff.changed?(diff, :state)
    refute Jido.Agent.Diff.changed?(diff, :agents)
    assert length(labeled(server, "worker")) == 3
    assert children -- members(server) == []
    stop_topology(server)
  end

  @tag :tmp_dir
  test "a mutated topology survives repeated File-backed hibernate and thaw", %{
    jido: jido,
    tmp_dir: path
  } do
    persistence = {Jido.Persistence.File, path: path}
    id = unique_id("saved-topology")

    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, Mutations,
        id: id,
        persistence: persistence,
        persistence_mode: :create
      )

    assert {:ok, add} = Mutations.workers_add_signal(%{count: 2})
    assert {:ok, _, _} = Server.call(server, add)
    assert :ok = Server.await_ready(server)
    assert {:ok, bind} = Mutations.workers_bind_signal(%{count: 3})
    assert {:ok, _, []} = Server.call(server, bind)
    assert :ok = Server.await_ready(server)
    assert {:ok, replace} = Mutations.observer_replace_signal()
    assert {:ok, accepted, _} = Server.call(server, replace)
    assert :ok = Server.await_ready(server)
    assert accepted.topology != Mutations.definition().topology
    assert {:ok, work} = Cell.work_signal(%{value: 9})
    for worker <- labeled(server, "worker"), do: assert({:ok, _, []} = Server.call(worker, work))
    snapshot = Server.snapshot(server)
    assert {:ok, portable} = Jido.Persistence.snapshot(snapshot.agent)

    restored =
      Enum.reduce(1..2, server, fn _, live ->
        monitors = monitor_runtime(Server.activation(live))
        assert :ok = Jido.hibernate(jido, live)
        assert_down(monitors)
        assert Jido.agent_count(jido) == 0
        assert {:ok, awake} = Jido.thaw(jido, Mutations, id, persistence: persistence)
        assert :ok = Server.await_ready(awake)
        assert Server.snapshot(awake).state_version == snapshot.state_version
        assert {:ok, ^portable} = Jido.Persistence.snapshot(Server.agent(awake))
        assert length(labeled(awake, "worker")) == 3
        assert length(labeled(awake, "replacement")) == 1
        # Each member restores its own confirmed commit.
        assert Enum.all?(labeled(awake, "worker"), &(Server.agent(&1).state.total == 9))
        awake
      end)

    stop_topology(restored)
    assert Jido.agent_count(jido) == 0
  end
end
