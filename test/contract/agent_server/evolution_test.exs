Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.EvolutionTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server2", async: true
  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Directive, as: R
  alias JidoTest.AgentEvolutionFixtures, as: E
  alias JidoTest.AgentServer.Fixtures, as: F
  import JidoTest.Eventually

  defmodule Upgrade do
    use Jido.Action, name: "server_live_upgrade"

    def run(%{snapshot: snapshot}, context) do
      if context[:observer],
        do: send(context.observer, {:upgrading, snapshot.agent.state.count, self()})

      if context[:gate], do: receive(do: (:release -> :ok))

      agent = %{
        snapshot.agent
        | vsn: snapshot.agent.vsn + 1,
          state: %{count: snapshot.agent.state.count + 10}
      }

      with {:ok, next} <- Jido.Persistence.snapshot(agent), do: {:ok, %{snapshot: next}}
    end
  end

  defp start(c, agent \\ nil, opts \\ []) do
    agent = agent || %{E.agent() | id: unique_id("evolution")}
    assert {:ok, server} = Jido.start_agent(c.jido, agent, opts)
    assert :ok = Server.await_ready(server)
    server
  end

  defp turn(server, directives), do: Server.call(server, E.signal(directives))

  defp settled(server) do
    assert_eventually(Server.status(server).phase == :idle)
    :ok
  end

  @tag obligation: "jido.agent_server2.I100"
  test "snapshots pair the accepted definition and state with their revision", c do
    server = start(c)
    initial = Server.snapshot(server)
    assert initial.state_version == 0
    assert {:ok, accepted, _} = turn(server, [D.route_add("new", E.Work)])
    assert %{agent: ^accepted, state_version: 1} = Server.snapshot(server)
    assert {:error, _} = turn(server, [D.route_remove("absent")])
    assert %{agent: ^accepted, state_version: 1} = Server.snapshot(server)
    assert {:ok, saved} = Jido.Persistence.snapshot(accepted)
    assert {:ok, ^accepted} = Jido.Persistence.restore(saved)
  end

  @tag obligation: "jido.agent_server2.I101"
  test "live upgrades serialize with Turns and preserve the previous snapshot until commit", c do
    agent =
      Agent.define!(%{
        name: "upgrade",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}]
      })
      |> Agent.instantiate!(id: unique_id("upgrade"))

    server = start(c, agent)
    pending = Server.submit(server, F.signal(%{mode: :gate}), context: %{observer: self()})
    assert_receive {:executing, work, _, _}
    observer = self()

    upgrade =
      Task.async(fn ->
        Server.upgrade(server, Upgrade, context: %{observer: observer, gate: true})
      end)

    assert_eventually(Server.status(server).admission.postponed == 1)
    assert %{agent: ^agent, state_version: 0} = Server.snapshot(server)
    send(work, :release)
    assert {:ok, _, []} = Server.await(pending)
    # The Action observer must be the test process, not the caller Task.
    assert_receive {:upgrading, 1, action}, 2_000
    assert Server.snapshot(server).state_version == 1
    queued = Server.submit(server, F.signal())
    send(action, :release)
    assert {:ok, upgraded, []} = Task.await(upgrade)
    assert upgraded.vsn == 2
    assert upgraded.state.count == 11
    assert {:ok, next, []} = Server.await(queued)
    assert next.state.count == 12
    assert %{agent: ^next, state_version: 3} = Server.snapshot(server)
  end

  @tag obligation: "jido.agent_server2.I101"
  test "invalid upgrades preserve the complete accepted Agent and revision", c do
    server = start(c)
    initial = Server.snapshot(server)

    for mode <- [:identity, :origin, :state, :directive, :result, :extra, :nonportable, :raise] do
      assert {:error, _} = Server.upgrade(server, E.BadUpgrade, context: %{mode: mode})
      assert Server.snapshot(server) == initial
    end

    assert {:error, _} = Server.upgrade(server, E.Flow)
    assert Server.snapshot(server) == initial
  end

  @tag obligation: "jido.agent_server2.I101"
  test "durable and local recovery retain a live upgrade", c do
    initial = %{E.agent() | id: unique_id("upgrade-recovery")}
    store = {Jido.Persistence.ETS, table: __MODULE__}
    server = start(c, initial, persistence: store)
    assert {:ok, upgraded, []} = Server.upgrade(server, Upgrade)

    assert {:ok, ^upgraded, 1} =
             Jido.Persistence.load_agent_with_revision(store, initial.module, initial.id,
               instance: c.jido
             )

    root = Server.activation(server)
    Process.exit(server, :kill)

    recovered =
      eventually(fn ->
        pid = Server.Supervisor.worker(root)
        if is_pid(pid) and pid != server, do: pid
      end)

    assert :ok = Server.await_ready(recovered)
    assert %{agent: ^upgraded, state_version: 1} = Server.snapshot(recovered)
  end

  @tag obligation: "jido.agent_server2.I102"
  test "runtime directives start, send, reply to the owner, and stop a permanent Agent", c do
    server = start(c)
    child = %{E.agent() | id: unique_id("runtime-child")}

    assert {:ok, _, _} =
             turn(server, [
               R.agent_start(child, :worker, restart: :permanent, meta: %{role: :worker})
             ])

    settled(server)
    assert %{worker: %{pid: worker}} = Server.children(server)

    assert {:ok, _, _} =
             turn(server, [R.agent_send(:worker, E.signal([D.route_add("extra", E.Work)]))])

    settled(server)
    assert_eventually(length(Server.agent(worker).routes) == 2)
    assert {:ok, _, _} = turn(worker, [R.owner_send(E.signal([D.route_add("reply", E.Work)]))])
    settled(worker)
    assert_eventually(length(Server.agent(server).routes) == 2)
    assert {:ok, _, _} = turn(server, [R.agent_stop(:worker)])
    settled(server)
    assert Server.children(server) == %{}
    refute Process.alive?(worker)
  end

  @tag obligation: "jido.agent_server2.I102"
  test "runtime requests reject remote placement and bad options before commit", c do
    server = start(c)
    initial = Server.snapshot(server)

    for directive <- [
          R.agent_start(E.Worker, :worker, node: :remote@invalid),
          R.agent_start(E.Worker, :worker, opts: %{unknown: true}),
          R.agent_start(E.Worker, :worker, opts: %{partition: "other"}),
          R.agent_start(E.Worker, :worker, opts: %{agent: E.agent()}),
          R.agent_start(E.Worker, nil),
          R.owner_send(E.signal([]))
        ] do
      assert {:error, _} = turn(server, [D.route_add("never", E.Work), directive])
      assert Server.snapshot(server) == initial
      assert Server.children(server) == %{}
    end

    assert {:ok, _, _} =
             turn(server, [
               R.agent_start(E.Worker, :worker,
                 opts: %{id: "explicit", state: %{count: 4}},
                 restart: :temporary
               )
             ])

    settled(server)
    assert Server.agent(Server.children(server).worker.pid).state.count == 4
  end

  @tag obligation: "jido.agent_server2.I96"
  test "topology count changes keep unchanged processes and connection edits keep all processes",
       c do
    initial = %{E.agent() | id: unique_id("topology")}
    server = start(c, initial)
    assert {:ok, _, _} = turn(server, [D.agent_add(:workers, E.Worker, count: 2)])
    assert :ok = Server.await_ready(server)
    before = Server.children(server)
    assert map_size(before) == 2
    first = before["$topology/workers/1"].pid
    second = before["$topology/workers/2"].pid
    assert {:ok, _, _} = turn(server, [D.agent_update(:workers, %{count: 3})])
    assert :ok = Server.await_ready(server)
    assert Server.children(server)["$topology/workers/1"].pid == first
    assert Server.children(server)["$topology/workers/2"].pid == second
    assert map_size(Server.children(server)) == 3

    edge = %{
      path: "work",
      from: %{kind: :agent, name: :root},
      to: %{kind: :agent, name: :workers},
      delivery: :broadcast
    }

    assert {:ok, _, _} =
             turn(server, [
               D.connection_add(edge.path, from: edge.from, to: edge.to, delivery: edge.delivery)
             ])

    assert :ok = Server.await_ready(server)
    assert Server.children(server)["$topology/workers/1"].pid == first

    assert {:ok, _, _} =
             turn(server, [
               D.agent_update(:workers, %{count: 1}),
               D.connection_remove(edge.path, from: edge.from, to: edge.to)
             ])

    assert :ok = Server.await_ready(server)
    assert map_size(Server.children(server)) == 1
    assert Server.children(server)["$topology/workers/1"].pid == first
    refute Process.alive?(second)
  end

  defmodule Reply do
    use Jido.Action, name: "topology_reply"

    def run(_, context) do
      signal = Jido.Signal.new!("received", %{amount: 1}, source: "/worker")
      {:ok, %{context.agent_state | count: context.agent_state.count + 1}, [D.emit(signal)]}
    end
  end

  defmodule FailRoot do
    use GenServer
    def start_link(_), do: {:error, :controlled_topology_failure}
    @impl true
    def init(value), do: {:ok, value}
  end

  defmodule FailPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{id: __MODULE__, start: {FailRoot, :start_link, [init]}}
  end

  defp worker(handler \\ F.Work) do
    Agent.define!(%{
      name: "worker",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [%{path: "work", handler: %{kind: :action, target: handler}}]
    })
  end

  @tag obligation: "jido.agent_server2.I96"
  test "startup binds initial inputs and a state-only commit resizes the topology", c do
    topology = %{
      agents: [
        %{
          name: :workers,
          definition: worker(),
          count: Agent.Topology.state(:count),
          initial_state: %{count: Agent.Topology.state(:count)}
        }
      ],
      connections: []
    }

    initial =
      Agent.define!(%{
        name: "bound",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)}),
        routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}],
        topology: topology
      })
      |> Agent.instantiate!(id: unique_id("bound"))

    server = start(c, initial)
    before = Server.children(server)["$topology/workers/1"].pid
    assert Server.agent(before).state.count == 1
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert :ok = Server.await_ready(server)
    after_children = Server.children(server)
    assert map_size(after_children) == 2
    refute after_children["$topology/workers/1"].pid == before
    assert Server.agent(after_children["$topology/workers/1"].pid).state.count == 2
    accepted = Server.snapshot(server)
    assert {:error, _} = Server.call(server, F.signal(%{amount: -2}))
    assert Server.snapshot(server) == accepted
    assert Server.children(server) == after_children
  end

  @tag obligation: "jido.agent_server2.I99"
  test "accepted connections route outputs through counted agents and back to the root", c do
    initial = %{E.agent() | id: unique_id("routing")}

    assert {:ok, initial, _} =
             Agent.mutate(initial, [
               D.route_add("received", F.Work),
               D.agent_add(:workers, worker(Reply), count: 2),
               D.connection_add("work",
                 from: %{kind: :agent, name: :root},
                 to: %{kind: :agent, name: :workers},
                 delivery: :broadcast
               ),
               D.connection_add("received",
                 from: %{kind: :agent, name: :workers},
                 to: %{kind: :agent, name: :root}
               )
             ])

    server = start(c, initial)
    assert {:ok, _, _} = turn(server, [D.emit(F.signal())])
    assert_eventually(Server.agent(server).state.count == 2)

    for {_, %{pid: pid}} <- Server.children(server),
        do: assert(Server.agent(pid).state.count == 1)
  end

  @tag obligation: "jido.agent_server2.I99"
  test "declared local buses route outputs and stop with the supervisor", c do
    bus = %{
      id: Jido.Plugin.Bus.DSL.id(),
      provider: Jido.Plugin.Bus.DSL,
      vsn: 1,
      data: %{buses: [%{name: :events}]}
    }

    topology = %{
      agents: [%{name: :worker, definition: worker()}],
      connections: [
        %{path: "work", from: %{kind: :agent, name: :root}, to: %{kind: :bus, name: :events}},
        %{path: "work", from: %{kind: :bus, name: :events}, to: %{kind: :agent, name: :worker}}
      ]
    }

    initial =
      Agent.define!(%{
        name: "bus",
        schema: E.agent().schema,
        routes: E.agent().routes,
        extensions: [bus],
        topology: topology
      })
      |> Agent.instantiate!(id: unique_id("bus"))

    server = start(c, initial)
    child = Server.children(server)["$topology/worker/1"].pid
    root = Server.activation(server)

    {{:topology_bus, :events}, bridge, _, _} =
      List.keyfind(Supervisor.which_children(root), {:topology_bus, :events}, 0)

    bus_pid = :sys.get_state(bridge).bus
    assert {:ok, _, _} = turn(server, [D.emit(F.signal())])
    assert_eventually(Server.agent(child).state.count == 1)
    Process.exit(server, :kill)

    recovered =
      eventually(fn ->
        pid = Server.Supervisor.worker(root)
        if is_pid(pid) and pid != server, do: pid
      end)

    assert :ok = Server.await_ready(recovered)
    next_child = Server.children(recovered)["$topology/worker/1"].pid
    assert {:ok, _, _} = turn(recovered, [D.emit(F.signal())])
    assert_eventually(Server.agent(next_child).state.count == 1)

    {{:topology_bus, :events}, next_bridge, _, _} =
      List.keyfind(Supervisor.which_children(root), {:topology_bus, :events}, 0)

    next_bus = :sys.get_state(next_bridge).bus
    assert :ok = Server.stop(recovered)
    refute Process.alive?(next_child)
    refute Process.alive?(next_bridge)
    refute Process.alive?(next_bus)
    refute Process.alive?(child)
    refute Process.alive?(bridge)
    refute Process.alive?(bus_pid)
  end

  @tag obligation: "jido.agent_server2.I98"
  test "replacement stops only the changed member and recovery rebuilds the accepted topology",
       c do
    server = start(c)
    assert {:ok, _, _} = turn(server, [D.agent_add(:one, worker()), D.agent_add(:two, worker())])
    assert :ok = Server.await_ready(server)
    before = Server.children(server)

    assert {:ok, accepted, _} =
             turn(server, [D.agent_replace(:one, worker(), initial_state: %{count: 9})])

    assert :ok = Server.await_ready(server)
    after_children = Server.children(server)
    refute after_children["$topology/one/1"].pid == before["$topology/one/1"].pid
    assert after_children["$topology/two/1"].pid == before["$topology/two/1"].pid
    root = Server.activation(server)
    Process.exit(server, :kill)

    recovered =
      eventually(fn ->
        pid = Server.Supervisor.worker(root)
        if is_pid(pid) and pid != server, do: pid
      end)

    assert :ok = Server.await_ready(recovered)
    assert Server.agent(recovered) == accepted
    assert Server.agent(Server.children(recovered)["$topology/one/1"].pid).state.count == 9
  end

  @tag capture_log: true
  @tag obligation: "jido.agent_server2.I98"
  test "a post-commit topology startup failure keeps the accepted checkpoint", c do
    initial = %{E.agent() | id: unique_id("failed-topology")}
    store = {Jido.Persistence.ETS, table: __MODULE__}
    server = start(c, initial, persistence: store)
    assert {:ok, definition, _} = Agent.mutate(worker(), [D.plugin_add(FailPlugin)])
    monitor = Process.monitor(server)
    assert {:ok, accepted, _} = turn(server, [D.agent_add(:broken, definition)])
    assert_receive {:DOWN, ^monitor, :process, ^server, _}, 3_000

    assert {:ok, restored, 1} =
             Jido.Persistence.load_agent_with_revision(store, initial.module, initial.id,
               instance: c.jido
             )

    assert restored.topology == accepted.topology
  end

  defmodule SchemaUpgrade do
    use Jido.Action, name: "server_schema_upgrade"
    @schema Zoi.object(%{total: Zoi.integer()})

    def run(%{snapshot: snapshot}, _) do
      target =
        snapshot.agent
        |> Agent.definition()
        |> Map.from_struct()
        |> Map.merge(%{
          vsn: 2,
          schema: @schema,
          routes: [%{path: "next", handler: %{kind: :action, target: E.Work}}]
        })
        |> Agent.define!()
        |> Agent.instantiate!(id: snapshot.agent.id, state: %{total: snapshot.agent.state.count})

      with {:ok, saved} <- Jido.Persistence.snapshot(target), do: {:ok, %{snapshot: saved}}
    end
  end

  @tag obligation: "jido.agent_server2.I101"
  test "an explicit upgrade changes schema and routes without using the source definition", c do
    server = start(c)
    assert {:ok, upgraded, []} = Server.upgrade(server, SchemaUpgrade)
    assert upgraded.vsn == 2
    assert upgraded.state == %{total: 0}
    assert Enum.map(upgraded.routes, & &1.path) == ["next"]
    assert {:error, _} = turn(server, [])

    assert {:ok, ^upgraded, []} =
             Server.call(server, Jido.Signal.new!("next", %{}, source: "/test"))

    assert Server.snapshot(server).state_version == 2
  end

  @tag obligation: "jido.agent_server2.I99"
  test "outputs from a mutation Turn use the accepted connections", c do
    server = start(c)
    edge = fn name -> [from: %{kind: :agent, name: :root}, to: %{kind: :agent, name: name}] end

    assert {:ok, _, _} =
             turn(server, [
               D.agent_add(:one, worker()),
               D.agent_add(:two, worker()),
               D.connection_add("work", edge.(:one))
             ])

    assert :ok = Server.await_ready(server)
    children = Server.children(server)

    assert {:ok, _, _} =
             turn(server, [
               D.connection_remove("work", edge.(:one)),
               D.connection_add("work", edge.(:two)),
               D.emit(F.signal())
             ])

    assert_eventually(Server.agent(children["$topology/two/1"].pid).state.count == 1)
    assert Server.agent(children["$topology/one/1"].pid).state.count == 0
    assert Server.children(server) == children
  end

  defmodule ReadyRoot do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)
    @impl true
    def init(init) do
      send(init.options[:observer], {:topology_ready_gate, self(), init.agent_server})

      receive do
        :release -> {:ok, init}
      end
    end
  end

  defmodule ReadyPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{id: __MODULE__, start: {ReadyRoot, :start_link, [init]}}
  end

  @tag obligation: "jido.agent_server2.I96"
  test "the next Turn waits until the accepted topology is ready", c do
    observer = Module.concat(__MODULE__, "Ready#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    server = start(c)

    assert {:ok, definition, _} =
             Agent.mutate(worker(), [D.plugin_add(ReadyPlugin, observer: observer)])

    assert {:ok, accepted, _} = turn(server, [D.agent_add(:worker, definition)])
    assert_receive {:topology_ready_gate, gate, _child}
    assert %{agent: ^accepted, state_version: 1} = Server.snapshot(server)
    refute Server.status(server).ready?
    pending = Server.submit(server, E.signal([]))
    assert_eventually(Server.status(server).admission.postponed == 1)
    send(gate, :release)
    assert :ok = Server.await_ready(server)
    assert {:ok, _, []} = Server.await(pending)
    assert Server.snapshot(server).state_version == 2
  end

  @tag obligation: "jido.agent_server2.I102"
  test "permanent runtime agents restart and temporary agents release their names", c do
    server = start(c)

    for restart <- [:permanent, :temporary] do
      assert {:ok, _, _} =
               turn(server, [
                 R.agent_start(Agent.definition(E.agent()), restart, restart: restart)
               ])

      settled(server)
      worker = Server.children(server)[restart].pid
      assert {:ok, _, _} = turn(worker, [R.server_stop()])

      if restart == :permanent do
        assert_eventually(
          match?(%{permanent: %{pid: pid}} when pid != worker, Server.children(server))
        )

        assert {:ok, _, _} = turn(server, [R.agent_stop(:permanent)])
        settled(server)
      else
        assert_eventually(Server.children(server) == %{})

        assert {:ok, _, _} =
                 turn(server, [R.agent_start(Agent.definition(E.agent()), :temporary)])

        settled(server)
        assert Map.has_key?(Server.children(server), :temporary)
      end
    end
  end

  @tag obligation: "jido.agent_server2.I100"
  test "startup snapshots reject provisional state", c do
    observer = Module.concat(__MODULE__, "Snapshot#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    initial = %{E.agent() | id: unique_id("snapshot-startup")}

    assert {:ok, initial, _} =
             Agent.mutate(initial, [D.plugin_add(ReadyPlugin, observer: observer)])

    startup = Task.async(fn -> Jido.start_agent(c.jido, initial) end)
    assert_receive {:topology_ready_gate, gate, server}

    try do
      assert {:error, :not_ready} = Server.snapshot(server)
    after
      send(gate, :release)
    end

    assert {:ok, ^server} = Task.await(startup)
    assert :ok = Server.await_ready(server)
    assert %{agent: ^initial, state_version: 0} = Server.snapshot(server)
  end

  @tag obligation: "jido.agent_server2.I99"
  test "topology connections take priority over default dispatch", c do
    initial = %{E.agent() | id: unique_id("default-dispatch")}

    assert {:ok, initial, _} =
             Agent.mutate(initial, [
               D.agent_add(:worker, worker()),
               D.connection_add("work",
                 from: %{kind: :agent, name: :root},
                 to: %{kind: :agent, name: :worker}
               )
             ])

    server = start(c, initial, default_dispatch: {:pid, target: self()})
    child = Server.children(server)["$topology/worker/1"].pid
    output = F.signal()
    assert {:ok, _, _} = turn(server, [D.emit(output)])
    settled(server)
    assert_eventually(Server.agent(child).state.count == 1)
    refute_received {:signal, ^output}
  end
end
