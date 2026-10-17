Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.RecoveryTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule Instance do
    use Jido, otp_app: :jido, namespace: "jido/test/server2-ref-instance"
  end

  defmodule LocalAgent do
    use Jido.Agent, name: "server2_local_checkpoint"

    agent do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0), handle: Zoi.any()})
    end

    routes do
      route "work", F.Work
    end

    @impl Jido.Agent
    def checkpoint(_, _), do: raise("local recovery must not serialize")

    @impl Jido.Agent
    def restore(_, _), do: raise("local recovery must not deserialize")
  end

  defmodule CommitPlugin do
    use Jido.Plugin

    def after_commit(nil, _, opts) do
      send(opts[:observer], {:post_commit, self()})
      receive do: (:release -> :ok)
    end
  end

  defmodule Resource do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      send(init.options[:observer], {:resource_init, self(), init})
      {:ok, init}
    end
  end

  defmodule Plugin do
    use Jido.Plugin
    def state_spec(_), do: {:resource, Zoi.integer() |> Zoi.default(7)}
    def child_spec(init), do: %{start: {Resource, :start_link, [init]}}
    def reduce(reduction, _), do: {:ok, reduction.plugin_state + 1}

    def await_ready(root, opts) do
      send(opts[:observer], {:ready_gate, self(), root})
      receive do: (:release -> :ok)
    end
  end

  setup do
    name = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), name)
    Map.put(F.setup_runtime(), :observer, name)
  end

  defp checkpoint_table(server) do
    {_phase, data} = :sys.get_state(server)
    data.activation_state
  end

  defp replace(server) do
    root = Server.activation(server)
    Process.exit(server, :kill)
    F.down(server)

    assert_eventually(
      match?(pid when is_pid(pid) and pid != server, Server.Activation.worker(root))
    )

    replacement = Server.Activation.worker(root)
    assert Server.await_ready(replacement) == :ok
    replacement
  end

  @tag obligation: ["jido.agent_server2.I70", "jido.agent_server2.I71", "jido.agent_server2.I72"]
  test "Refs route calls casts submissions reads and stop in the exact partition", c do
    {:ok, first} = Server.start(agent: c.agent, jido: c.jido, partition: "west")
    {:ok, second} = Server.start(agent: c.agent, jido: c.jido, partition: "east")
    {:ok, ref} = Jido.agent_ref(c.jido, c.agent.id, partition: "west")
    assert Map.keys(Map.from_struct(ref)) |> Enum.sort() == [:id, :namespace, :partition]
    assert Jido.resolve_agent(c.jido, ref) == {:ok, first}
    assert Jido.children(c.jido, ref) == %{}
    assert Jido.await_ready(c.jido, ref) == :ok

    for read <- [
          &Jido.agent(c.jido, ref, &1),
          &Jido.status(c.jido, ref, &1),
          &Jido.plugin_state(c.jido, ref, F.Gate, &1),
          &Jido.children(c.jido, ref, &1)
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = read.(-1)
    end

    assert {:ok, %{state: %{count: 1}}, []} = Jido.call(c.jido, ref, F.signal())
    pending = Jido.submit(c.jido, ref, F.signal())
    assert {:ok, %{state: %{count: 2}}, []} = Jido.await(pending)
    assert Jido.cast(c.jido, ref, F.signal()) == :ok
    assert_eventually(Jido.status(c.jido, ref).state_version == 3)
    assert Jido.agent(c.jido, ref).state.count == 3
    assert Server.agent(second) == c.agent
    replacement = replace(first)
    assert Jido.resolve_agent(c.jido, ref) == {:ok, replacement}
    assert Jido.agent(c.jido, ref).state.count == 3
    assert {:ok, %{state: %{count: 4}}, []} = Jido.call(c.jido, ref, F.signal())
    root = Server.activation(replacement)
    assert Jido.stop_agent_ref(c.jido, ref) == :ok
    refute Process.alive?(root)
    assert Jido.resolve_agent(c.jido, ref) == {:error, :not_found}
    assert Process.alive?(second)
  end

  @tag obligation: ["jido.agent_server2.I70", "jido.agent_server2.I71"]
  test "Ref identity errors and unavailable Registry do not start work", c do
    {:ok, server} = Server.start(agent: c.agent, jido: c.jido)
    {:ok, ref} = Jido.agent_ref(c.jido, c.agent.id)

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.call(c.jido, %{ref | namespace: "other"}, F.signal())

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.resolve_agent(c.jido, %{ref | partition: 7})

    assert Jido.call(c.jido, %{ref | id: "absent"}, F.signal()) == {:error, :not_found}
    assert Server.agent(server) == c.agent
    :sys.suspend(c.jido_pid)
    registry = Process.whereis(Jido.registry_name(c.jido))

    try do
      Process.exit(registry, :kill)
      F.down(registry)
      assert Jido.resolve_agent(c.jido, ref) == {:error, :unavailable}
    after
      :sys.resume(c.jido_pid)
    end
  end

  @tag obligation: ["jido.agent_server2.I70", "jido.agent_server2.I71", "jido.agent_server2.I74"]
  test "worker loss during a resolved call returns unavailable without replay", c do
    {:ok, server} = Server.start(agent: c.agent, jido: c.jido)
    {:ok, ref} = Jido.agent_ref(c.jido, c.agent.id)
    root = Server.activation(server)
    :sys.suspend(server)
    request = Task.async(fn -> Jido.call(c.jido, ref, F.signal()) end)

    assert_eventually(
      server
      |> Process.info(:messages)
      |> elem(1)
      |> Enum.any?(&match?({:"$gen_call", _, _}, &1))
    )

    Process.exit(server, :kill)
    assert Task.await(request) == {:error, :unavailable}

    assert_eventually(
      match?(pid when is_pid(pid) and pid != server, Server.Activation.worker(root))
    )

    replacement = Server.Activation.worker(root)
    assert Server.await_ready(replacement) == :ok
    assert Jido.agent(c.jido, ref) == c.agent
    assert Jido.status(c.jido, ref).state_version == 0
  end

  @tag obligation: ["jido.agent_server2.I70", "jido.agent_server2.I73"]
  test "Plugin reconstruction uses restored state and revision before Ref admission opens", c do
    agent =
      Agent.define!(
        name: "recover_plugin",
        schema: c.agent.schema,
        plugins: [{Plugin, observer: c.observer}],
        routes: [{"work", F.Work}]
      )
      |> Agent.instantiate!(id: "recover-plugin")

    {:ok, server} = Server.start(agent: agent, jido: c.jido)
    {:ok, ref} = Jido.agent_ref(c.jido, agent.id)
    assert_receive {:resource_init, root, %{plugin_state: 7, state_version: 0}}, 1_000
    assert_receive {:ready_gate, gate, ^root}, 1_000
    assert Jido.resolve_agent(c.jido, ref) == {:error, :recovering}
    assert Jido.call(c.jido, ref, F.signal()) == {:error, :recovering}
    send(gate, :release)
    assert Server.await_ready(server) == :ok
    assert {:ok, committed, []} = Jido.call(c.jido, ref, F.signal())
    assert committed.state.resource == 8
    Process.exit(root, :kill)
    F.down(server)

    assert_receive {:resource_init, fresh,
                    %{agent_server: replacement, plugin_state: 8, state_version: 1}},
                   1_000

    assert fresh != root
    assert replacement != server
    assert_receive {:ready_gate, next_gate, ^fresh}, 1_000
    assert Jido.resolve_agent(c.jido, ref) == {:error, :recovering}
    assert Server.agent(replacement) == committed
    send(next_gate, :release)
    assert Server.await_ready(replacement) == :ok
    assert Jido.resolve_agent(c.jido, ref) == {:ok, replacement}
    assert Jido.plugin_state(c.jido, ref, Plugin) == {:ok, 8}
  end

  @tag obligation: ["jido.agent_server2.I69", "jido.agent_server2.I71"]
  test "instance startup and direct startup use the same Ref protocol", c do
    {:ok, first} = Jido.start_agent(c.jido, %{c.agent | id: "first"})
    {:ok, first_ref} = Jido.agent_ref(c.jido, "first")
    {:ok, second} = Server.start(agent: c.agent, jido: c.jido)
    {:ok, ref} = Jido.agent_ref(c.jido, c.agent.id)
    assert {:ok, %{state: %{count: 1}}, []} = Jido.call(c.jido, first_ref, F.signal())
    assert Jido.agent(c.jido, first_ref).id == "first"
    assert Jido.status(c.jido, first_ref).state_version == 1
    assert {:ok, _, []} = Jido.call(c.jido, ref, F.signal())

    assert {:ok, %{state: %{count: 2}}, []} =
             c.jido |> Jido.submit(first_ref, F.signal()) |> Jido.await()

    assert Jido.agent(c.jido, ref) == Server.agent(second)
    assert Jido.stop_agent_ref(c.jido, first_ref) == :ok
    refute Process.alive?(first)
  end

  @tag obligation: "jido.agent_server2.I71"
  test "generated instance wrappers keep pending reply ownership and caller timeout", c do
    start_supervised!({Instance, []})
    {:ok, server} = Server.start(agent: c.agent, jido: Instance)
    {:ok, ref} = Instance.agent_ref(c.agent.id)
    pending = Instance.submit(ref, F.signal(%{mode: :gate}), context: %{observer: self()})
    assert_receive {:executing, action, _, _}, 1_000
    assert Instance.await(pending, 0) == {:error, :timeout}
    assert Instance.abandon(pending) == :ok
    assert catch_exit(Instance.call(ref, F.signal(), timeout: 0))
    assert Server.status(server).active != nil
    send(action, :release)
    assert_eventually(Instance.status(ref).state_version == 2)
    assert Instance.agent(ref).state.count == 2
  end

  @tag obligation: ["jido.agent_server2.I72", "jido.agent_server2.I74"]
  test "unchanged success publishes once and failures never replace the checkpoint", c do
    server = F.start(c)
    table = checkpoint_table(server)
    assert :ets.lookup(table, :checkpoint) == [{:checkpoint, c.agent, 0}]
    assert {:ok, same, []} = Server.call(server, F.signal(%{amount: 0}))
    assert same == c.agent
    assert :ets.lookup(table, :checkpoint) == [{:checkpoint, same, 1}]

    for mode <- [:fail, :invalid] do
      assert {:error, _} = Server.call(server, F.signal(%{mode: mode}))
      assert :ets.lookup(table, :checkpoint) == [{:checkpoint, same, 1}]
    end

    timed = F.start(c, turn_timeout: 1)
    assert {:error, :turn_timeout} = Server.call(timed, F.signal(%{mode: :gate}))
    assert Server.agent(replace(timed)) == c.agent
    assert :ets.lookup(table, :checkpoint) == [{:checkpoint, same, 1}]
    active = F.blocked(server, c.runner)
    assert Server.cancel(server) == :ok
    assert {:error, :cancelled} = Server.await(active.pending)
    assert :ets.lookup(table, :checkpoint) == [{:checkpoint, same, 1}]
    recovered = replace(server)
    assert Server.agent(recovered) == same
    assert Server.status(recovered).state_version == 1
  end

  @tag obligation: ["jido.agent_server2.I72", "jido.agent_server2.I74"]
  test "a crash before publication restores the prior commit and stops active execution", c do
    server = F.start(c)
    assert {:ok, committed, []} = Server.call(server, F.signal())
    turn = F.blocked(server, c.runner)
    recovered = replace(server)
    F.down(turn.action)
    F.down(turn.worker)
    assert {:error, _} = Server.await(turn.pending)
    assert Server.agent(recovered) == committed
    assert Server.status(recovered).state_version == 1
    assert {:ok, %{state: %{count: 2}}, []} = Server.call(recovered, F.signal())
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I72", "jido.agent_server2.I74"]
  test "a published commit survives a lost caller reply without replay", c do
    server = F.start(c)
    table = checkpoint_table(server)
    observer = self()

    requestor =
      Task.async(fn ->
        pending = Server.submit(server, F.signal(), context: %{observer: observer})
        send(observer, :submitted)
        receive do: (:collect -> Server.await(pending))
      end)

    assert_receive :submitted, 1_000
    assert_receive {:executing, _, _, _}, 1_000
    assert_eventually(match?([{:checkpoint, _, 1}], :ets.lookup(table, :checkpoint)))
    assert Server.status(server).phase == :idle
    Task.shutdown(requestor, :brutal_kill)
    recovered = replace(server)
    assert Server.agent(recovered).state.count == 1
    assert Server.status(recovered).state_version == 1
    refute_received {:executing, _, _, _}
    assert {:ok, %{state: %{count: 2}}, []} = Server.call(recovered, F.signal())
  end

  @tag obligation: ["jido.agent_server2.I72", "jido.agent_server2.I74"]
  test "recovery preserves commit during hooks and directives without replay", c do
    observer = self()

    handler = fn _, _ ->
      send(observer, {:post_commit, self()})
      receive do: (:release -> :ok)
    end

    for mode <- [:hook, :directive] do
      agent =
        if mode == :hook,
          do: %{c.agent | plugins: c.agent.plugins ++ [{CommitPlugin, observer: c.observer}]},
          else: c.agent

      server = F.start(%{c | agent: agent}, directive_handler: handler)
      directives = if mode == :directive, do: [%F.Effect{}], else: []
      signal = F.signal(%{mode: :batch, directives: directives})
      assert {:ok, committed, ^directives} = Server.call(server, signal)
      assert_receive {:post_commit, task}, 1_000
      assert Server.status(server).active.stage == :effects
      recovered = replace(server)
      F.down(task)
      assert Server.agent(recovered) == committed
      assert Server.status(recovered).state_version == 1
      refute_received {:post_commit, _}
      assert Server.stop(recovered) == :ok
    end
  end

  @tag obligation: ["jido.agent_server2.I73", "jido.agent_server2.I75"]
  test "local checkpoints preserve schema-permitted local state without serialization callbacks",
       c do
    agent = LocalAgent.instantiate!(id: "local-handle", state: %{handle: self()})

    server = F.start(%{c | agent: agent})

    assert {:ok, committed, []} =
             Server.call(server, F.signal(), context: %{temporary: make_ref()})

    assert committed.state.handle == self()
    recovered = replace(server)
    assert Server.agent(recovered) === committed
    assert Server.status(recovered).state_version == 1
    assert :ets.lookup(checkpoint_table(recovered), :checkpoint) == [{:checkpoint, committed, 1}]
  end

  @tag obligation: ["jido.agent_server2.I73", "jido.agent_server2.I75"]
  test "missing corrupt and incompatible checkpoints stop recovery without fresh state", c do
    for corrupt <- [:missing, :shape, :revision, :revision_type, :id, :state, :definition, :vsn] do
      server = F.start(c)
      root = Server.activation(server)
      table = checkpoint_table(server)

      entry =
        case corrupt do
          :shape -> {:checkpoint, :invalid, 1}
          :revision -> {:checkpoint, c.agent, -1}
          :revision_type -> {:checkpoint, c.agent, "1"}
          :id -> {:checkpoint, %{c.agent | id: "other"}, 1}
          :state -> {:checkpoint, %{c.agent | state: %{count: "bad", probe: 0}}, 1}
          :definition -> {:checkpoint, %{c.agent | routes: []}, 1}
          :vsn -> {:checkpoint, %{c.agent | vsn: 2}, 1}
          :missing -> nil
        end

      if entry, do: :ets.insert(table, entry), else: :ets.delete(table, :checkpoint)
      Process.exit(server, :kill)
      F.down(root)
      refute Process.alive?(server)
      assert :ets.info(table) == :undefined
    end
  end

  @tag obligation: "jido.agent_server2.I75"
  test "complete activation replacement drops its local checkpoint", c do
    server = F.start(c)
    table = checkpoint_table(server)
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert Server.stop(server) == :ok
    assert :ets.info(table) == :undefined
    fresh = F.start(c)
    assert Server.agent(fresh) == c.agent
    assert Server.status(fresh).state_version == 0

    bare =
      start_supervised!(%{
        id: make_ref(),
        start: {Server, :start_link, [[agent: c.agent, runner: c.runner]]},
        restart: :temporary
      })

    assert Server.activation(bare) == nil
    assert Server.children(bare) == %{}
    assert {:ok, %{state: %{count: 1}}, []} = Server.call(bare, F.signal())
    assert Server.status(bare).state_version == 1
    assert Server.stop(bare) == :ok
  end

  @tag obligation: "jido.agent_server2.I76"
  test "checkpoint conflict or loss cannot report success or run effects", c do
    observer = self()

    for failure <- [:conflict, :missing] do
      server = F.start(c, directive_handler: fn _, _ -> send(observer, :unexpected_effect) end)
      root = Server.activation(server)
      table = checkpoint_table(server)

      case failure do
        :conflict -> :ets.insert(table, {:checkpoint, c.agent, 7})
        :missing -> :ets.delete(table, :checkpoint)
      end

      assert {:error, _} = Server.call(server, F.signal(%{mode: :directive}))
      F.down(root)
      refute Process.alive?(server)
      refute_received :unexpected_effect
      F.clean(c.runner)
    end
  end
end
