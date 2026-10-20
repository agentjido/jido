Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.PluginRuntime.RuntimeTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: false
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  @moduletag capture_log: true

  defmodule Root do
    use GenServer

    def start_link(init) do
      case {GenServer.start_link(__MODULE__, init), init.options[:start_info]} do
        {{:ok, pid}, true} -> {:ok, pid, :plugin_start_info}
        {result, _} -> result
      end
    end

    def handle_call(:owner, _from, init), do: {:reply, init.agent_server, init}

    def init(init) do
      observer = init.options[:observer]
      send(observer, {:plugin_root, init.module, self(), init})

      case init.options[:start_mode] do
        :fail ->
          {:stop, :controlled_start_failure}

        :gate ->
          receive do
            :release -> {:ok, init}
          after
            180 -> {:ok, init}
          end

        _ ->
          {:ok, init}
      end
    end
  end

  defmodule ExitTrappingRoot do
    @moduledoc false

    def start_link(init) do
      starter = self()

      {:ok, root} =
        Task.start_link(fn ->
          Process.flag(:trap_exit, true)
          Process.flag(:priority, Keyword.get(init.options, :priority, :normal))

          if init.options[:owned_table] do
            table = :ets.new(__MODULE__, [:set, :public])
            :ets.insert(table, {:ready, true})
            send(init.options[:observer], {:plugin_owned_table, init.module, self(), table})
          end

          send(starter, {:root_started, self()})
          send(init.options[:observer], {:plugin_root, init.module, self(), init})
          wait()
        end)

      receive do
        {:root_started, ^root} -> :ok
      end

      if init.options[:start_mode] == :gate do
        send(init.options[:observer], {:plugin_start_blocked, init.module, self(), root})

        receive do
          :release -> :ok
        after
          180 -> :ok
        end
      end

      {:ok, root}
    end

    defp wait do
      receive do
        {:EXIT, _, _} -> wait()
      end
    end
  end

  defmodule TrappingFirst do
    use Jido.Plugin

    def child_spec(init),
      do: %{
        id: __MODULE__,
        start: {ExitTrappingRoot, :start_link, [init]},
        shutdown: Keyword.get(init.options, :shutdown, 20)
      }

    defdelegate await_ready(pid, opts),
      to: JidoTest.AgentServer.PluginRuntime.RuntimeTest.First,
      as: :readiness
  end

  defmodule TrappingSecond do
    use Jido.Plugin

    defdelegate child_spec(init), to: TrappingFirst
  end

  defmodule TrappingLeaf do
    @moduledoc false

    def start_link(opts) do
      starter = self()

      {:ok, leaf} =
        Task.start_link(fn ->
          Process.flag(:trap_exit, true)

          if shared_name = opts[:shared_link] do
            shared = Process.whereis(shared_name)
            Process.link(shared)
            send(opts[:observer], {:plugin_leaf_linked, self(), shared})
          end

          send(starter, {:leaf_started, self()})
          send(opts[:observer], {:plugin_leaf, self()})
          wait()
        end)

      receive do
        {:leaf_started, ^leaf} -> :ok
      end

      if opts[:leaf_start_mode] == :gate do
        send(opts[:observer], {:plugin_leaf_start_blocked, self(), leaf})

        receive do
          :release -> :ok
        after
          180 -> :ok
        end
      end

      {:ok, leaf}
    end

    defp wait do
      receive do
        {:EXIT, _, _} -> wait()
      end
    end
  end

  defmodule SupervisorRoot do
    use Supervisor

    def start_link(init),
      do: Supervisor.start_link(__MODULE__, init, Keyword.take(init.options, [:name]))

    def init(init) do
      send(init.options[:observer], {:plugin_root, init.module, self(), init})

      Supervisor.init(
        [
          %{
            id: TrappingLeaf,
            start: {TrappingLeaf, :start_link, [init.options]},
            shutdown: 20,
            restart: :permanent
          }
        ],
        strategy: :one_for_one
      )
    end
  end

  defmodule SharedRoot do
    use GenServer

    def start_link(name), do: GenServer.start_link(__MODULE__, nil, name: name)

    def init(nil) do
      Process.flag(:trap_exit, true)
      {:ok, nil}
    end

    def handle_call(:ping, _from, state), do: {:reply, :pong, state}
    def handle_info({:EXIT, _, _}, state), do: {:noreply, state}
  end

  defmodule NamedRoot do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init, name: __MODULE__)
    def init(init), do: {:ok, init}
    def handle_call(:init, _, init), do: {:reply, init, init}
  end

  defmodule NamedPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{start: {NamedRoot, :start_link, [init]}}
  end

  defmodule IgnoredRoot do
    def start_link(_), do: :ignore
  end

  defmodule IgnoredPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{start: {IgnoredRoot, :start_link, [init]}}
  end

  defmodule SupervisorPlugin do
    use Jido.Plugin

    def child_spec(init),
      do: %{id: __MODULE__, start: {SupervisorRoot, :start_link, [init]}, type: :supervisor}
  end

  defmodule First do
    use Jido.Plugin
    def state_spec(_), do: {:first, Zoi.integer() |> Zoi.default(7)}
    def prepare(_, _), do: {:ok, %{prepared: :first}}
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}
    def await_ready(pid, opts), do: readiness(pid, opts)
    def admit(pid, admission, opts), do: admission(pid, admission, opts)

    def readiness(pid, opts) do
      send(opts[:observer], {:readiness, self(), pid})

      case opts[:ready_mode] do
        :probe ->
          owner = GenServer.call(pid, :owner)
          send(opts[:observer], {:readiness_probe, Server.await_ready(owner)})
          :ok

        :gate ->
          receive do
            :release -> :ok
          end

        :fail ->
          {:error, :controlled_readiness_failure}

        _ ->
          :ok
      end
    end

    def admission(pid, admission, opts) do
      send(opts[:observer], {:admission, admission.plugin, self(), pid, admission})

      case admission.signal.data[:admit_mode] do
        :reject ->
          {:error, :denied}

        :invalid ->
          :invalid

        :raise ->
          raise "private admission failure"

        :gate ->
          receive do
            :release -> {:ok, %{pid: pid}}
          end

        :reentrant ->
          server = admission.caller_context.server
          result = Server.call(server, F.signal())
          send(opts[:observer], {:admission_probe, result})
          {:ok, %{pid: pid}}

        _ ->
          {:ok, %{pid: pid}}
      end
    end
  end

  defmodule Second do
    use Jido.Plugin
    def state_spec(_), do: {:second, Zoi.integer() |> Zoi.default(9)}
    def prepare(_, _), do: {:ok, %{prepared: :second}}
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}
    defdelegate await_ready(pid, opts), to: First, as: :readiness
    defdelegate admit(pid, admission, opts), to: First, as: :admission
  end

  defmodule AdmissionOnly do
    use Jido.Plugin

    def admit(nil, admission, opts) do
      send(opts[:observer], {:stateless_admission, admission})
      {:ok, :no_runtime}
    end
  end

  setup do
    name = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), name)
    F.setup_runtime()
  end

  defp live_agent(opts, second_opts) do
    {:registered_name, observer} = Process.info(self(), :registered_name)
    opts = Keyword.put(opts, :observer, observer)
    second_opts = Keyword.put(second_opts, :observer, observer)

    Jido.Agent.define!(%{
      name: "server_live_plugins",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      extensions: [
        %{id: F.Gate.id(), provider: F.Gate, vsn: F.Gate.vsn(), data: %{}},
        %{id: First.id(), provider: First, vsn: First.vsn(), data: Map.new(opts)},
        %{id: Second.id(), provider: Second, vsn: Second.vsn(), data: Map.new(second_opts)}
      ],
      routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}]
    })
    |> Jido.Agent.instantiate!(id: "server-live-instance")
  end

  defp start_live(c, opts \\ [], runtime_opts \\ []) do
    agent = live_agent(Keyword.put(opts, :observer, self()), observer: self())
    server = F.start(%{c | agent: agent}, runtime_opts)
    {server, agent}
  end

  defp trapping_agent(first_opts \\ [], second_opts \\ []) do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    Jido.Agent.define!(%{
      name: "server_trapping_plugins",
      schema: Zoi.object(%{}),
      extensions: [
        %{
          id: TrappingFirst.id(),
          provider: TrappingFirst,
          vsn: TrappingFirst.vsn(),
          data: Map.new(Keyword.put(first_opts, :observer, observer))
        },
        %{
          id: TrappingSecond.id(),
          provider: TrappingSecond,
          vsn: TrappingSecond.vsn(),
          data: Map.new(Keyword.put(second_opts, :observer, observer))
        }
      ]
    })
    |> Jido.Agent.instantiate!(id: "server-trapping-instance")
  end

  defp supervisor_agent(first_opts, second_opts) do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    Jido.Agent.define!(%{
      name: "server_supervisor_plugins",
      schema: Zoi.object(%{}),
      extensions: [
        %{
          id: SupervisorPlugin.id(),
          provider: SupervisorPlugin,
          vsn: SupervisorPlugin.vsn(),
          data: Map.new(Keyword.put(first_opts, :observer, observer))
        },
        %{
          id: TrappingSecond.id(),
          provider: TrappingSecond,
          vsn: TrappingSecond.vsn(),
          data: Map.new(Keyword.put(second_opts, :observer, observer))
        }
      ]
    })
    |> Jido.Agent.instantiate!(id: "server-supervisor-instance")
  end

  defp watch_root(module) do
    assert_receive {:plugin_root, ^module, root, _}, 1_000
    watch_process(root)
  end

  defp watch_start(c, agent, module) do
    F.start_activation(%{c | agent: agent}, readiness_timeout: 100)
    assert_receive {:plugin_root, ^module, root, init}, 1_000
    {init.agent_server, watch_process(root)}
  end

  defp watch_leaf do
    assert_receive {:plugin_leaf, leaf}, 1_000
    watch_process(leaf)
  end

  defp watch_process(pid) do
    ref = Process.monitor(pid)

    on_exit(fn ->
      monitor = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    end)

    {pid, ref}
  end

  defp assert_root_down({root, ref}),
    do: assert_receive({:DOWN, ^ref, :process, ^root, _}, 1_000)

  defp start_required(c, plugin) do
    agent =
      Jido.Agent.define!(%{
        name: "required_plugin",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        extensions: [JidoTest.AgentContract.contribution(plugin)],
        routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}]
      })
      |> Jido.Agent.instantiate!(id: "required-plugin")

    {:ok, root} =
      start_supervised(
        Supervisor.child_spec({Server, agent: agent, runner: c.runner},
          id: make_ref(),
          restart: :temporary
        )
      )

    root
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "a required Plugin cannot borrow a named root outside its activation", c do
    external = start_supervised!({NamedRoot, :external})
    root = start_required(c, NamedPlugin)
    F.down(root)
    assert Process.alive?(external)
    assert GenServer.call(external, :init) == :external
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "an ignored required Plugin root cannot publish readiness", c do
    root = start_required(c, IgnoredPlugin)
    F.down(root)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "a Plugin supervisor recovers its own leaf without restarting its Agent", c do
    server = F.start(%{c | agent: supervisor_agent([], [])})
    plugin = watch_root(SupervisorPlugin)
    {leaf, _} = first_leaf = watch_leaf()
    assert Server.await_ready(server) == :ok
    generation = Server.status(server).generation
    Process.exit(leaf, :kill)
    assert_root_down(first_leaf)
    assert_receive {:plugin_leaf, replacement}, 1_000
    assert replacement != leaf
    assert Server.status(server).generation == generation
    assert Process.alive?(elem(plugin, 0))
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "a bare worker cannot start a runtime Plugin", c do
    assert {:error, %Jido.Error.ValidationError{}} =
             Server.start_link(agent: live_agent([], []), runner: c.runner)
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I2"]
  test "all roots start before readiness, with scoped immutable Init and no handles in state",
       c do
    {server, agent} =
      start_live(c, [ready_mode: :gate],
        jido: c.jido,
        runner: Jido.exec_runner_name(c.jido),
        partition: "plugin-runtime"
      )

    assert_receive {:plugin_root, First, first, init}, 1_000
    assert_receive {:plugin_root, Second, second, _}, 1_000
    assert_receive {:readiness, task, ^first}, 1_000
    assert init.agent_server == server
    assert init.plugin_state == 7
    assert init.state_version == 0
    assert init.jido == c.jido
    assert init.partition == "plugin-runtime"
    assert Server.agent(server) == agent
    assert %{phase: :initializing, ready?: false, plugin_count: 3} = Server.status(server)
    assert {:error, :not_ready} = Server.call(server, F.signal())
    assert {:error, :not_running} = Server.cancel(server)
    waiter = Task.async(fn -> Server.await_ready(server) end)
    send(task, :release)
    assert Task.await(waiter) == :ok
    assert Server.status(server).ready?
    assert Process.alive?(second)
    assert Server.agent(server) == agent
    Server.stop(server)
    F.down(first)
    F.down(second)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I2"
  test "caller readiness timeout does not cancel bootstrap", c do
    {server, _} = start_live(c, ready_mode: :gate)
    assert_receive {:readiness, task, _}, 1_000
    assert catch_exit(Server.await_ready(server, 0))
    assert Server.agent(server).state.count == 0
    send(task, :release)
    assert Server.await_ready(server) == :ok
    assert {:ok, _, []} = Server.call(server, F.signal())
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "readiness deadline stops startup tasks and all provisional roots", c do
    {server, _} = start_live(c, [ready_mode: :gate], readiness_timeout: 100)
    assert_receive {:plugin_root, First, first, _}, 1_000
    assert_receive {:plugin_root, Second, second, _}, 1_000
    assert_receive {:readiness, task, _}, 1_000
    ref = Process.monitor(server)
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :readiness_timeout}}, 1_000
    for pid <- [first, second, task], do: F.down(pid)
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "the readiness budget closes admission while bounded child startup settles", c do
    {server, first} = watch_start(c, live_agent([start_mode: :gate], []), First)
    ref = Process.monitor(server)
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :readiness_timeout}}, 1_000
    assert_root_down(first)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I2"
  test "a readiness callback cannot wait for its own readiness", c do
    {server, _} = start_live(c, ready_mode: :probe)
    assert_receive {:readiness_probe, {:error, :reentrant_turn}}, 1_000
    assert Server.await_ready(server) == :ok
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I3"
  test "a delayed readiness result cannot pass the startup deadline", c do
    {server, _} = start_live(c, [ready_mode: :gate], readiness_timeout: 150)
    assert_receive {:readiness, task, _}, 1_000
    :sys.suspend(server)
    on_exit(fn -> if Process.alive?(server), do: :sys.resume(server) end)
    send(task, :release)
    F.down(task)
    F.elapsed(170)
    ref = Process.monitor(server)
    :sys.resume(server)
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :readiness_timeout}}, 1_000
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "startup and readiness errors stop every provisional root", c do
    for mode <- [:start, :ready] do
      second =
        [observer: self()] ++
          if(mode == :start, do: [start_mode: :fail], else: [ready_mode: :fail])

      agent = live_agent([observer: self()], second)
      server = F.start(%{c | agent: agent})
      assert_receive {:plugin_root, First, first, _}, 1_000
      ref = Process.monitor(server)
      assert_receive {:DOWN, ^ref, :process, ^server, _}, 1_000
      F.down(first)
    end
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "owner loss during child start stops the provisional process", c do
    {server, _} = start_live(c, start_mode: :gate)
    assert_receive {:plugin_root, First, first, _}, 1_000
    Process.exit(server, :kill)
    F.down(server)
    F.down(first)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "runtime root loss stops the activation and the other root", c do
    {server, _} = start_live(c)
    assert_receive {:plugin_root, First, first, _}, 1_000
    assert_receive {:plugin_root, Second, second, _}, 1_000
    assert Server.await_ready(server) == :ok
    ref = Process.monitor(server)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^ref, :process, ^server, :shutdown}, 1_000
    F.down(second)
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I4", "jido.agent_server.plugin_runtime.I5"]
  test "live admission follows declaration order and keeps pure and runtime inputs separate", c do
    {server, agent} = start_live(c)
    assert Server.await_ready(server) == :ok
    assert {:ok, saved, []} = Server.call(server, F.signal(), context: %{observer: self()})
    assert_receive {:admission, First, _, first, first_admission}, 1_000
    assert_receive {:admission, Second, _, second, second_admission}, 1_000
    assert first_admission.prepared_input == %{prepared: :first}
    assert first_admission.plugin_state == 7
    assert first_admission.state_version == 0
    assert second_admission.prepared_input == %{prepared: :second}
    assert_receive {:executing, _, context, _}, 1_000

    assert context.plugin_inputs[First] == %Jido.Plugin.Input{
             prepared: %{prepared: :first},
             runtime: %{pid: first}
           }

    assert context.plugin_inputs[Second].runtime == %{pid: second}
    assert saved.state == %{agent.state | count: 1}

    assert {:ok, 7} =
             Jido.Plugin.state(%Jido.Plugin.Init{
               agent_server: server,
               agent_id: agent.id,
               module: First
             })

    assert {:ok, _, []} = Server.call(server, F.signal())
    assert_receive {:admission, First, _, _, %{state_version: 1}}, 1_000
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I4"
  test "rejected, invalid, or raised admission never executes or commits", c do
    {server, agent} = start_live(c)
    assert Server.await_ready(server) == :ok

    for mode <- [:reject, :invalid, :raise] do
      assert {:error, _} =
               Server.call(server, F.signal(%{admit_mode: mode}), context: %{observer: self()})

      F.unchanged(server, agent)
      refute_received {:executing, _, _, _}
    end

    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I5"
  test "live admission is bounded by turn timeout and permits cancellation and reads", c do
    {server, agent} = start_live(c)
    assert Server.await_ready(server) == :ok
    pending = Server.submit(server, F.signal(%{admit_mode: :gate}))
    assert_receive {:admission, First, task, _, _}, 1_000
    assert Server.agent(server) == agent
    assert Server.cancel(server) == :ok
    assert Server.await(pending) == {:error, :cancelled}
    F.down(task)
    F.unchanged(server, agent)
    F.clean(c.runner)
    Server.stop(server)
    {timed, original} = start_live(c, [], turn_timeout: 100)
    assert Server.await_ready(timed) == :ok
    pending = Server.submit(timed, F.signal(%{admit_mode: :gate}))
    assert_receive {:admission, First, blocked, _, _}, 1_000
    assert Server.await(pending, 1_000) == {:error, :turn_timeout}
    F.down(blocked)
    F.unchanged(timed, original)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I5"
  test "live admission cannot synchronously submit its own turn", c do
    {server, _} = start_live(c)
    assert Server.await_ready(server) == :ok

    assert {:ok, _, []} =
             Server.call(server, F.signal(%{admit_mode: :reentrant}), context: %{server: server})

    assert_receive {:admission_probe, {:error, :reentrant_turn}}, 1_000
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I2"]
  test "instance lookup advertises readiness only after all Plugin checks", c do
    {server, agent} =
      start_live(c, [ready_mode: :gate],
        jido: c.jido,
        runner: Jido.exec_runner_name(c.jido),
        partition: "live"
      )

    assert_receive {:readiness, task, _}, 1_000
    assert Server.whereis(c.jido, agent.id, partition: "live") == nil
    assert Jido.whereis_agent(c.jido, agent.id, partition: "live") == nil
    send(task, :release)
    assert Server.await_ready(server) == :ok
    assert Server.whereis(c.jido, agent.id, partition: "live") == server
    assert Jido.whereis_agent(c.jido, agent.id, partition: "live") == server
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "owner death after readiness stops both Plugin roots", c do
    {server, _} = start_live(c)
    assert_receive {:plugin_root, First, first, _}, 1_000
    assert_receive {:plugin_root, Second, second, _}, 1_000
    assert Server.await_ready(server) == :ok
    Process.exit(server, :kill)
    F.down(server)
    F.down(first)
    F.down(second)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "owner death stops Plugin roots that trap exits", c do
    server = F.start(%{c | agent: trapping_agent()})
    first = watch_root(TrappingFirst)
    second = watch_root(TrappingSecond)
    assert Server.await_ready(server) == :ok
    server_ref = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
    assert_root_down(first)
    assert_root_down(second)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "root loss stops another Plugin root that traps exits", c do
    server = F.start(%{c | agent: trapping_agent()})
    {first, _} = first_root = watch_root(TrappingFirst)
    second = watch_root(TrappingSecond)
    assert Server.await_ready(server) == :ok
    server_ref = Process.monitor(server)
    Process.exit(first, :kill)
    assert_root_down(first_root)

    assert_receive {:DOWN, ^server_ref, :process, ^server, :shutdown},
                   1_000

    assert_root_down(second)
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "readiness timeout stops established Plugin roots that trap exits", c do
    server = F.start(%{c | agent: trapping_agent(ready_mode: :gate)}, readiness_timeout: 100)
    first = watch_root(TrappingFirst)
    second = watch_root(TrappingSecond)
    assert_receive {:readiness, readiness, _root}, 1_000
    readiness_ref = Process.monitor(readiness)
    server_ref = Process.monitor(server)

    assert_receive {:DOWN, ^server_ref, :process, ^server, {:shutdown, :readiness_timeout}},
                   1_000

    assert_root_down(first)
    assert_root_down(second)
    assert_receive {:DOWN, ^readiness_ref, :process, ^readiness, _}, 1_000
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "startup timeout closes admission and cleans a bounded exit-trapping start", c do
    {server, {root, _} = tracked} =
      watch_start(c, trapping_agent(start_mode: :gate), TrappingFirst)

    assert_receive {:plugin_start_blocked, TrappingFirst, starter, ^root}, 1_000
    starter_process = watch_process(starter)
    server_ref = Process.monitor(server)

    assert_receive {:DOWN, ^server_ref, :process, ^server, {:shutdown, :readiness_timeout}},
                   1_000

    assert_root_down(tracked)
    assert_root_down(starter_process)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "owner death settles a bounded start and recovers the required root", c do
    server = F.start(%{c | agent: trapping_agent(start_mode: :gate)})
    {root, _} = tracked = watch_root(TrappingFirst)
    assert_receive {:plugin_start_blocked, TrappingFirst, starter, ^root}, 1_000
    activation = starter
    server_ref = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
    assert_root_down(tracked)
    assert Process.alive?(activation)
    replacement = Server.Supervisor.worker(activation)
    assert replacement != server
    assert Server.await_ready(replacement) == :ok
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "root loss settles a bounded sibling start before group recovery", c do
    server = F.start(%{c | agent: trapping_agent([], start_mode: :gate)})
    {first, _} = first_root = watch_root(TrappingFirst)
    {second, _} = second_root = watch_root(TrappingSecond)
    assert_receive {:plugin_start_blocked, TrappingSecond, starter, ^second}, 1_000
    activation = starter
    server_ref = Process.monitor(server)
    Process.exit(first, :kill)
    assert_root_down(first_root)

    assert_receive {:DOWN, ^server_ref, :process, ^server, :shutdown},
                   1_000

    assert_root_down(second_root)
    assert Process.alive?(activation)
    replacement = Server.Supervisor.worker(activation)
    assert replacement != server
    assert Server.await_ready(replacement) == :ok
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "startup timeout stops an established exit-trapping root while its sibling starts", c do
    # Read the worker from the startup event. A supervisor lookup can wait
    # behind the sibling's blocked start until after the readiness deadline.
    {server, {first, _} = first_root} =
      watch_start(
        c,
        trapping_agent([owned_table: true, shutdown: :brutal_kill], start_mode: :gate),
        TrappingFirst
      )

    server_ref = Process.monitor(server)
    assert_receive {:plugin_owned_table, TrappingFirst, ^first, table}, 1_000
    {second, _} = second_root = watch_root(TrappingSecond)
    assert_receive {:plugin_start_blocked, TrappingSecond, starter, ^second}, 1_000
    starter_process = watch_process(starter)

    assert_receive {:DOWN, ^server_ref, :process, ^server, {:shutdown, :readiness_timeout}},
                   1_000

    assert_root_down(first_root)
    assert :ets.info(table) == :undefined
    assert_root_down(second_root)
    assert_root_down(starter_process)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "stop confirms root death before returning when kill delivery is pending", c do
    server =
      F.start(%{
        c
        | agent:
            trapping_agent(
              [owned_table: true, shutdown: :brutal_kill, priority: :low],
              start_mode: :gate
            )
      })

    {first, _} = first_root = watch_root(TrappingFirst)
    assert_receive {:plugin_owned_table, TrappingFirst, ^first, table}, 1_000
    {second, _} = second_root = watch_root(TrappingSecond)
    assert_receive {:plugin_start_blocked, TrappingSecond, starter, ^second}, 1_000
    starter_process = watch_process(starter)

    # Private state only locates the process whose scheduling we control.
    runtime = Server.activation(server)
    schedulers = :erlang.system_flag(:schedulers_online, 1)
    on_exit(fn -> :erlang.system_flag(:schedulers_online, schedulers) end)

    try do
      for pid <- [server, runtime] do
        :sys.replace_state(pid, fn state ->
          Process.flag(:priority, :max)
          state
        end)
      end

      priority = Process.flag(:priority, :max)

      try do
        # The low-priority root can handle its kill only when cleanup waits.
        # Check its resource before any process probe can flush that signal.
        assert Server.stop(server) == :ok
        assert :ets.info(table) == :undefined
      after
        Process.flag(:priority, priority)
      end
    after
      :erlang.system_flag(:schedulers_online, schedulers)
    end

    assert_root_down(first_root)
    assert_root_down(second_root)
    assert_root_down(starter_process)
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I1"
  test "owner death shuts down an established Supervisor tree while another root starts", c do
    server = F.start(%{c | agent: supervisor_agent([], start_mode: :gate)})
    supervisor = watch_root(SupervisorPlugin)
    leaf = watch_leaf()
    {second, _} = second_root = watch_root(TrappingSecond)
    assert_receive {:plugin_start_blocked, TrappingSecond, starter, ^second}, 1_000
    activation = starter
    server_ref = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
    assert_root_down(supervisor)
    assert_root_down(leaf)
    assert_root_down(second_root)
    assert Process.alive?(activation)
    replacement = Server.Supervisor.worker(activation)
    assert replacement != server
    assert Server.await_ready(replacement) == :ok
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "startup timeout stops a blocked Supervisor root and its exit-trapping descendant", c do
    {server, {root, _} = supervisor} =
      watch_start(c, supervisor_agent([leaf_start_mode: :gate], []), SupervisorPlugin)

    {leaf, _} = descendant = watch_leaf()
    assert_receive {:plugin_leaf_start_blocked, ^root, ^leaf}, 1_000
    server_ref = Process.monitor(server)

    assert_receive {:DOWN, ^server_ref, :process, ^server, {:shutdown, :readiness_timeout}},
                   1_000

    assert_root_down(supervisor)
    assert_root_down(descendant)
  end

  @tag obligation: ["jido.agent_server.plugin_runtime.I1", "jido.agent_server.plugin_runtime.I3"]
  test "blocked named Supervisor startup stops owned descendants and preserves a shared link",
       c do
    suffix = System.unique_integer([:positive])
    shared_name = Module.concat(__MODULE__, "Shared#{suffix}")
    root_name = Module.concat(__MODULE__, "NamedRoot#{suffix}")
    shared = start_supervised!({SharedRoot, shared_name})

    {server, {root, _} = supervisor} =
      watch_start(
        c,
        supervisor_agent([name: root_name, leaf_start_mode: :gate, shared_link: shared_name], []),
        SupervisorPlugin
      )

    {leaf, _} = descendant = watch_leaf()
    assert Process.whereis(root_name) == root
    assert_receive {:plugin_leaf_linked, ^leaf, ^shared}, 1_000
    assert_receive {:plugin_leaf_start_blocked, ^root, ^leaf}, 1_000
    server_ref = Process.monitor(server)

    assert_receive {:DOWN, ^server_ref, :process, ^server, {:shutdown, :readiness_timeout}},
                   1_000

    assert_root_down(supervisor)
    assert_root_down(descendant)
    assert Process.alive?(shared)
    assert GenServer.call(shared, :ping) == :pong
  end

  @tag obligation: [
         "jido.agent_server.plugin_runtime.I1",
         "jido.agent_server.plugin_runtime.I2",
         "jido.agent_server.plugin_runtime.I4"
       ]
  test "a root start result with info reaches readiness and supplies the live runtime ref", c do
    {server, _} = start_live(c, start_info: true)
    assert_receive {:plugin_root, First, first, _}, 1_000
    assert_receive {:plugin_root, Second, second, _}, 1_000
    first_ref = Process.monitor(first)
    second_ref = Process.monitor(second)
    assert Server.await_ready(server) == :ok
    assert {:ok, _, []} = Server.call(server, F.signal(), context: %{observer: self()})
    assert_receive {:admission, First, _, ^first, _}, 1_000
    assert_receive {:executing, _, context, _}, 1_000
    assert context.plugin_inputs[First].runtime == %{pid: first}
    :ok = Server.stop(server)
    refute Process.alive?(first)
    refute Process.alive?(second)
    assert_receive {:DOWN, ^first_ref, :process, ^first, _}, 1_000
    assert_receive {:DOWN, ^second_ref, :process, ^second, _}, 1_000
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I4"
  test "Plugins without runtime roots can still admit transient input", c do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    agent =
      Jido.Agent.define!(%{
        name: "stateless_live_plugin",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        extensions: [
          %{
            id: AdmissionOnly.id(),
            provider: AdmissionOnly,
            vsn: AdmissionOnly.vsn(),
            data: %{observer: observer}
          }
        ],
        routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}]
      })
      |> Jido.Agent.instantiate!(id: "stateless-live")

    server = F.start(%{c | agent: agent})
    assert Server.await_ready(server) == :ok
    assert {:ok, _, []} = Server.call(server, F.signal(), context: %{observer: self()})
    assert_receive {:stateless_admission, _}, 1_000
    assert_receive {:executing, _, context, _}, 1_000
    assert context.plugin_inputs[AdmissionOnly].runtime == :no_runtime
  end

  @tag obligation: "jido.agent_server.plugin_runtime.I3"
  test "invalid readiness or default dispatch options fail before startup", c do
    for opts <- [
          [readiness_timeout: :infinity],
          [readiness_timeout: -1],
          [default_dispatch: :bad]
        ] do
      assert {:error, _} =
               Server.start_link(Keyword.merge([agent: c.agent, runner: c.runner], opts))

      assert {:error, _} = Server.validate_defaults(opts)
    end
  end
end
