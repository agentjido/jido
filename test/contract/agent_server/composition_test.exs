Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.CompositionTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false
  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  import JidoTest.Eventually
  @moduletag capture_log: true

  defmodule Worker do
    use Jido.Agent, name: "composition_runtime_worker"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "work", JidoTest.AgentServer.Fixtures.Work
    end
  end

  defmodule Root do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      send(init.options[:observer], {:plugin_started, self(), init})

      if init.options[:fail_start],
        do: {:stop, :controlled_start_failure},
        else: {:ok, %{init: init, paused: false}}
    end

    def handle_call({:pause, mode}, _, state) do
      if mode == :fail,
        do: {:reply, {:error, :pause_failed}, state},
        else: {:reply, :ok, %{state | paused: true}}
    end

    def handle_call(:resume, _, state), do: {:reply, :ok, %{state | paused: false}}
    def handle_call(:paused?, _, state), do: {:reply, state.paused, state}
  end

  defmodule Cache do
    use Jido.Plugin
    def state_spec(_), do: {:cache, Zoi.integer() |> Zoi.default(5)}
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}

    def quiesce(runtime, opts) do
      send(opts[:observer], {:quiescing, runtime, self()})
      if opts[:gate], do: receive(do: (:release -> :ok))
      GenServer.call(runtime, {:pause, opts[:pause_mode]})
    end

    def after_commit(runtime, commit, opts) do
      send(opts[:observer], {:composition_hook, __MODULE__, runtime, commit.state_version})
      :ok
    end

    def resume(runtime, opts) do
      send(opts[:observer], {:resuming, runtime})
      GenServer.call(runtime, :resume)
    end
  end

  defmodule Observer do
    use Jido.Plugin

    def after_commit(runtime, commit, opts) do
      send(opts[:observer], {:composition_hook, __MODULE__, runtime, commit.state_version})
      :ok
    end
  end

  defmodule UnsafeCache do
    use Jido.Plugin
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}
  end

  setup do
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    Map.put(F.setup_runtime(), :observer, observer)
  end

  defp agent(topology \\ %{}, plugins \\ []) do
    Agent.define!(%{
      name: "composed",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}],
      topology: topology,
      extensions:
        Enum.map(
          plugins,
          fn declaration ->
            {provider, options} =
              case declaration do
                {provider, options} -> {provider, options}
                provider -> {provider, []}
              end

            %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: Map.new(options)}
          end
        )
    })
    |> Agent.instantiate!(id: "composed")
  end

  defp turn(server, directives),
    do: Server.call(server, F.signal(%{mode: :batch, directives: directives}))

  @tag obligation: "jido.agent_server2.I95"
  test "route mutations commit as data and a failed batch keeps the revision", c do
    server = F.start(%{c | agent: agent()})
    directive = Directive.route_add("other", %{kind: :action, target: F.Work})
    assert {:ok, accepted, [^directive]} = turn(server, [directive])
    assert Enum.map(accepted.routes, & &1.path) == ["work", "other"]
    assert Server.status(server).state_version == 1
    assert {:error, _} = turn(server, [Directive.route_remove("missing")])
    assert Server.agent(server) == accepted
    assert Server.status(server).state_version == 1
    assert {:ok, next, []} = Server.call(server, F.signal(%{}, "other"))
    assert next.state.count == 2
  end

  @tag obligation: ["jido.agent_server2.I95", "jido.agent_server2.I96", "jido.agent_server2.I99"]
  test "topology mutations start accepted members", c do
    initial = agent()
    assert :ok = Server.CompositionRuntime.validate_runtime(%{agent: initial})
    member = Directive.agent_add(:worker, Worker)
    assert {:ok, candidate, _} = Agent.mutate(initial, [member])
    assert :ok = Server.CompositionRuntime.validate_runtime(%{agent: candidate})
    server = F.start(%{c | agent: initial})
    assert {:ok, _, [^member]} = turn(server, [member])
    assert :ok = Server.await_ready(server)
    assert Server.agent(server).topology == candidate.topology
    assert Server.status(server).state_version == 1
    assert map_size(Server.children(server)) == 1
  end

  @tag obligation: "jido.agent_server2.I98"
  test "worker recovery restores accepted routes and Plugins", c do
    server = F.start(%{c | agent: agent()})
    root = Server.activation(server)
    assert :ok = Server.await_ready(server)

    assert {:ok, accepted, _} =
             turn(server, [
               Directive.route_add("other", %{kind: :action, target: F.Work}),
               Directive.plugin_add(Cache, observer: c.observer)
             ])

    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, _, %{state_version: 1}}
    Process.exit(server, :kill)

    assert_eventually(
      is_pid(Server.Supervisor.worker(root)) and Server.Supervisor.worker(root) != server
    )

    worker = Server.Supervisor.worker(root)
    assert :ok = Server.await_ready(worker)
    assert Server.agent(worker) == accepted
    assert Server.status(worker).state_version == 1
    assert_receive {:plugin_started, _, %{state_version: 1}}
  end

  @tag obligation: "jido.agent_server2.I98"
  test "durable restore uses accepted routes and Plugins before resource startup", c do
    store =
      {Jido.Persistence.ETS,
       table: Module.concat(__MODULE__, "Store#{System.unique_integer([:positive])}")}

    initial = agent()
    context = %{agent: initial, runner: Jido.exec_runner_name(c.jido)}
    server = F.start(context, jido: c.jido, persistence: store)
    assert :ok = Server.await_ready(server)

    assert {:ok, accepted, _} =
             turn(server, [
               Directive.route_add("other", %{kind: :action, target: F.Work}),
               Directive.plugin_add(Cache, observer: c.observer)
             ])

    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, _, %{state_version: 1}}
    assert :ok = Server.stop(server)
    restored = F.start(context, jido: c.jido, persistence: store, persistence_mode: :restore)
    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored) == accepted
    assert Server.status(restored).state_version == 1
    assert_receive {:plugin_started, _, %{plugin_state: 5, state_version: 1}}
  end

  @tag obligation: "jido.agent_server2.I97"
  test "Plugins install, configure from committed state, and stop with explicit removal", c do
    server = F.start(%{c | agent: agent()})
    assert {:ok, _, _} = turn(server, [Directive.plugin_add(Cache, observer: c.observer)])
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, first, %{plugin_state: 5, state_version: 1}}
    ref = Process.monitor(first)

    assert {:ok, _, _} =
             turn(server, [Directive.plugin_configure(Cache, observer: c.observer, capacity: 99)])

    assert :ok = Server.await_ready(server)
    assert_receive {:quiescing, ^first, _}
    assert_receive {:DOWN, ^ref, :process, ^first, _}
    assert_receive {:plugin_started, second, %{plugin_state: 5, state_version: 2}}
    assert second != first
    ref = Process.monitor(second)
    assert {:ok, _, _} = turn(server, [Directive.plugin_remove(Cache, state: :discard)])
    assert :ok = Server.await_ready(server)
    assert_receive {:DOWN, ^ref, :process, ^second, _}
    assert Server.agent(server).state == %{count: 3}
    assert Agent.runtime_plugins(Server.agent(server)) == []
  end

  @tag obligation: "jido.agent_server2.I97"
  test "unsafe live Plugin change fails before commit and pause failure resumes", c do
    server = F.start(%{c | agent: agent(%{}, [{UnsafeCache, observer: c.observer}])})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, root, _}
    assert {:error, _} = turn(server, [Directive.plugin_remove(UnsafeCache)])
    assert Server.status(server).state_version == 0
    assert Process.alive?(root)

    other =
      agent(%{}, [{Cache, observer: c.observer, pause_mode: :fail}]) |> Map.put(:id, "other")

    server = F.start(%{c | agent: other})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, root, _}
    assert {:error, _} = turn(server, [Directive.plugin_remove(Cache, state: :discard)])
    assert_receive {:resuming, ^root}
    refute GenServer.call(root, :paused?)
    assert Server.status(server).state_version == 0
  end

  @tag obligation: "jido.agent_server2.I97"
  test "cancelling Plugin preparation resumes resources without publishing a candidate", c do
    server = F.start(%{c | agent: agent(%{}, [{Cache, observer: c.observer, gate: true}])})
    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, root, _}

    pending =
      Server.submit(
        server,
        F.signal(%{mode: :batch, directives: [Directive.plugin_remove(Cache, state: :discard)]})
      )

    assert_receive {:quiescing, ^root, _task}, 1_000
    assert :ok = Server.cancel(server)
    assert {:error, :cancelled} = Server.await(pending)
    assert_receive {:resuming, ^root}
    assert Server.status(server).state_version == 0
    assert Process.alive?(root)
  end

  @tag obligation: ["jido.agent_server2.I95", "jido.agent_server2.I98"]
  test "committed resource failure does not undo the saved target or admit another turn", c do
    store =
      {Jido.Persistence.ETS,
       table: Module.concat(__MODULE__, "FailedStore#{System.unique_integer([:positive])}")}

    initial = agent()

    server =
      F.start(%{agent: initial, runner: Jido.exec_runner_name(c.jido)},
        jido: c.jido,
        persistence: store
      )

    assert :ok = Server.await_ready(server)
    root = Server.activation(server)
    ref = Process.monitor(root)

    assert {:ok, target, _} =
             turn(server, [Directive.plugin_add(Cache, observer: c.observer, fail_start: true)])

    assert_receive {:DOWN, ^ref, :process, ^root, _}, 1_000

    assert {:ok, ^target, 1} =
             Jido.Persistence.load_agent_with_revision(store, initial.module, initial.id,
               instance: c.jido
             )
  end

  @tag obligation: "jido.agent_server2.I97"
  test "configuration commits notify unchanged Plugins and later turns use the new runtime", c do
    server =
      F.start(%{
        c
        | agent: agent(%{}, [{Observer, observer: c.observer}, {Cache, observer: c.observer}])
      })

    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, first, _}

    assert {:ok, _, _} =
             turn(server, [Directive.plugin_configure(Cache, observer: c.observer, capacity: 2)])

    assert :ok = Server.await_ready(server)
    assert_receive {:plugin_started, second, %{state_version: 1}}
    assert second != first
    assert_receive {:composition_hook, Observer, nil, 1}
    refute_received {:composition_hook, Cache, _, 1}
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert_receive {:composition_hook, Observer, nil, 2}
    assert_receive {:composition_hook, Cache, ^second, 2}
  end

  @tag obligation: "jido.agent_server2.I95"
  test "a bare worker rejects composition changes before committing", c do
    bare =
      start_supervised!(%{
        id: make_ref(),
        start: {Server, :start_link, [[agent: agent(), runner: c.runner]]}
      })

    assert {:error, _} = turn(bare, [Directive.plugin_add(Observer, observer: c.observer)])
    assert Agent.runtime_plugins(Server.agent(bare)) == []
    assert Server.status(bare).state_version == 0
    assert Server.alive?(bare)
  end
end
