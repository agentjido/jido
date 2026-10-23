Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Durable.EvolutionTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.agent_server.durable", async: true

  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentEvolutionFixtures, as: E
  alias JidoTest.AgentServer.Fixtures, as: F
  import JidoTest.Eventually

  defmodule Upgrade do
    use Jido.Action,
      name: "server_live_upgrade"

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

  defmodule SchemaUpgrade do
    use Jido.Action,
      name: "server_schema_upgrade"

    @schema Zoi.object(%{total: Zoi.integer()})

    def run(%{snapshot: snapshot}, _) do
      target =
        snapshot.agent
        |> Agent.definition()
        |> Map.from_struct()
        |> Map.merge(%{
          vsn: 2,
          schema: @schema,
          routes: [
            %{
              path: "next",
              handler: %{kind: :action, target: E.Work},
              state: %{source: :output, path: []}
            }
          ]
        })
        |> Agent.define!()
        |> Agent.instantiate!(id: snapshot.agent.id, state: %{total: snapshot.agent.state.count})

      with {:ok, saved} <- Jido.Persistence.snapshot(target), do: {:ok, %{snapshot: saved}}
    end
  end

  defmodule ReadyRoot do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init) do
      send(init.options[:observer], {:snapshot_ready_gate, self(), init.agent_server})
      receive do: (:release -> {:ok, init})
    end
  end

  defmodule ReadyPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{id: __MODULE__, start: {ReadyRoot, :start_link, [init]}}
  end

  defp start(c, agent \\ nil, opts \\ []) do
    agent = agent || %{E.agent() | id: unique_id("evolution")}
    assert {:ok, server} = Jido.start_agent(c.jido, agent, opts)
    assert :ok = Server.await_ready(server)
    server
  end

  defp turn(server, directives), do: Server.call(server, E.signal(directives))

  @tag obligation: "jido.agent_server.durable.I11"
  test "snapshots pair the accepted definition and state with their revision", c do
    server = start(c)
    initial = Server.snapshot(server)
    assert initial.state_version == 0

    assert {:ok, accepted, _} =
             turn(server, [
               D.route_add("new", E.Work)
             ])

    assert %{agent: ^accepted, state_version: 1} = Server.snapshot(server)
    assert {:error, _} = turn(server, [D.route_remove("absent")])
    assert %{agent: ^accepted, state_version: 1} = Server.snapshot(server)
    assert {:ok, saved} = Jido.Persistence.snapshot(accepted)
    assert {:ok, ^accepted} = Jido.Persistence.restore(saved)
  end

  @tag obligation: "jido.agent_server.durable.I12"
  test "live upgrades serialize with Turns and preserve the previous snapshot until commit", c do
    agent =
      Agent.define!(%{
        name: "upgrade",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [
          %{
            path: "work",
            handler: %{kind: :action, target: F.Work},
            state: %{source: :output, path: []}
          }
        ]
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

  @tag obligation: "jido.agent_server.durable.I12"
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

  @tag obligation: [
         "jido.agent_server.durable.I12",
         "jido.agent_server.durable.I13"
       ]
  test "upgrade options are closed and accept the documented Map form", c do
    server = start(c)
    initial = Server.snapshot(server)

    for opts <- [
          [unknown: true],
          [context: %{}, context: %{}],
          [context: self()],
          [timeout: -1],
          :invalid
        ] do
      assert {:error, _} = Server.upgrade(server, Upgrade, opts)
      assert Server.snapshot(server) == initial
    end

    assert {:ok, upgraded, []} = Server.upgrade(server, Upgrade, %{context: %{}})
    assert upgraded.vsn == 2
  end

  @tag obligation: "jido.agent_server.durable.I12"
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

  @tag obligation: "jido.agent_server.durable.I12"
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

  @tag obligation: "jido.agent_server.durable.I11"
  test "startup snapshots reject provisional state", c do
    observer = Module.concat(__MODULE__, "Snapshot#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    initial = %{E.agent() | id: unique_id("snapshot-startup")}

    assert {:ok, initial, _} =
             Agent.mutate(initial, [D.plugin_add(ReadyPlugin, observer: observer)])

    startup = Task.async(fn -> Jido.start_agent(c.jido, initial) end)
    assert_receive {:snapshot_ready_gate, gate, server}, 1_000

    try do
      assert {:error, :not_ready} = Server.snapshot(server)
    after
      send(gate, :release)
    end

    assert {:ok, ^server} = Task.await(startup)
    assert :ok = Server.await_ready(server)
    assert %{agent: ^initial, state_version: 0} = Server.snapshot(server)
  end
end
