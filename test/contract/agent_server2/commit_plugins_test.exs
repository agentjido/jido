Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer2.CommitPluginsTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false
  alias Jido.AgentServer2, as: Server
  alias JidoTest.AgentServer2.Fixtures, as: F
  import JidoTest.Eventually
  @moduletag capture_log: true

  defmodule Effect do
    use Jido.Agent.Directive
    defstruct [:label, mode: :ok]
  end

  defmodule First do
    use Jido.Plugin
    def state_spec(_), do: {:first, Zoi.integer() |> Zoi.default(7)}
    def directives(_), do: [Effect]
    def reduce(reduction, _), do: {:ok, reduction.plugin_state + 1}
    def after_commit(nil, commit, opts), do: notify(commit, opts)

    def notify(commit, opts) do
      send(opts[:observer], {:committed, commit.plugin, self(), commit})
      outcome(opts[:mode])
    end

    def dispatch(nil, directive, context, opts) do
      send(opts[:observer], {:dispatched, self(), directive, context})
      outcome(directive.mode)
    end

    def outcome(:gate) do
      receive do
        :release -> :ok
      end
    end

    def outcome(:probe) do
      server = JidoTest.AgentServer2.CommitPluginsTest.Owner
      result = Server.call(server, F.signal())
      send(JidoTest.AgentServer2.CommitPluginsTest, {:callback_probe, result})
      :ok
    end

    def outcome(:linked_child) do
      Task.async(fn ->
        send(JidoTest.AgentServer2.CommitPluginsTest, {:linked_callback_child, self()})

        receive do
          :release -> :ok
        end
      end)
      |> Task.await(:infinity)
    end

    def outcome(:fail), do: {:error, :controlled_failure}
    def outcome(:invalid), do: :invalid
    def outcome(:raise), do: raise("private callback failure")
    def outcome(_), do: :ok
  end

  defmodule Live do
    use Jido.Plugin
    def state_spec(_), do: {:first, Zoi.integer() |> Zoi.default(7)}
    def directives(_), do: [Effect]
    def child_spec(init), do: %{id: __MODULE__, start: {Agent, :start_link, [fn -> init end]}}

    def after_commit(root, commit, opts) do
      send(opts[:observer], {:runtime_hook, root})
      First.notify(commit, opts)
    end

    def dispatch(root, directive, context, opts) do
      send(opts[:observer], {:runtime_dispatch, root})
      First.dispatch(nil, directive, context, opts)
    end
  end

  defmodule Second do
    use Jido.Plugin
    def state_spec(_), do: {:second, Zoi.integer() |> Zoi.default(9)}
    def after_commit(nil, commit, opts), do: First.notify(commit, opts)
  end

  setup do
    Process.register(self(), __MODULE__)
    F.setup_runtime()
  end

  defp start(c, mode \\ :ok, opts \\ []) do
    {plugin, mode} =
      case mode do
        {:live, mode} -> {Live, mode}
        mode -> {First, mode}
      end

    {mode, second_mode} = if mode == :last_gate, do: {:ok, :gate}, else: {mode, :ok}

    agent =
      Jido.Agent.define!(
        name: "commit_plugins",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugins: [
          {plugin, [observer: __MODULE__, mode: mode]},
          {Second, [observer: __MODULE__, mode: second_mode]}
        ],
        routes: [{"work", F.Work}]
      )
      |> Jido.Agent.instantiate!(id: "commit-plugins")

    F.start(%{c | agent: agent}, opts)
  end

  defp batch(ds), do: F.signal(%{mode: :batch, directives: ds})

  @tag obligation: "jido.agent_server2.I55"
  test "hooks run after commit in declaration order, even without directives", c do
    server = start(c, :gate)
    assert {:ok, saved, []} = Server.call(server, F.signal())
    assert saved.state.first == 8
    assert_receive {:committed, First, hook, commit}, 1_000
    assert commit.plugin_state == 8
    assert commit.state_version == 1
    assert commit.agent_id == saved.id
    assert commit.turn_id == Server.status(server).active.turn_id
    assert Server.agent(server) == saved
    assert {:error, :not_running} = Server.cancel(server)
    pending = Server.submit(server, F.signal())
    assert {:error, :timeout} = Server.await(pending, 0)
    send(hook, :release)
    assert_receive {:committed, Second, _, second}, 1_000
    assert second.plugin_state == 9
    assert second.state_version == 1
    assert {:ok, %{state: %{count: 2}}, []} = Server.await(pending)
    assert_receive {:committed, First, next_hook, %{state_version: 2}}, 1_000
    send(next_hook, :release)
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_outcome.committed?
  end

  @tag obligation: "jido.agent_server2.I56"
  test "hook failures stop later hooks and effects without changing turn success", c do
    for mode <- [:fail, :invalid, :raise] do
      server = start(c, mode)
      assert {:ok, saved, [_]} = Server.call(server, batch([%Effect{}]))
      assert_receive {:committed, First, _, _}, 1_000
      assert_eventually(Server.status(server).phase == :idle)
      assert Server.status(server).last_effect_outcome.status == :failed
      assert Server.status(server).last_outcome.status == :succeeded
      assert Server.agent(server) == saved
      refute_received {:committed, Second, _, _}
      refute_received {:dispatched, _, _, _}
      Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server2.I57"
  test "hook budget stops blocked work and preserves commit before queue replay", c do
    server = start(c, :gate, commit_timeout: 100, directive_timeout: 1_000)
    assert {:ok, saved, [_]} = Server.call(server, batch([%Effect{}]))
    assert_receive {:committed, First, hook, _}, 1_000
    ref = Process.monitor(hook)
    pending = Server.submit(server, F.signal(%{}, "missing"))
    assert_receive {:DOWN, ^ref, :process, ^hook, :killed}, 1_000
    assert {:error, _} = Server.await(pending)
    assert Server.agent(server) == saved
    assert Server.status(server).last_effect_outcome.status == :timed_out
    refute_received {:dispatched, _, _, _}
  end

  @tag obligation: "jido.agent_server2.I58"
  test "owned directives use Plugin dispatch after all hooks with a narrow committed context",
       c do
    server = start(c, :ok, directive_handler: fn _, _ -> flunk("fallback used") end)
    signal = batch([%Effect{label: :one}, %Effect{label: :two}])
    assert {:ok, saved, [_, _]} = Server.call(server, signal, context: %{token: :local})
    assert_receive {:committed, First, _, _}, 1_000
    assert_receive {:committed, Second, _, _}, 1_000
    assert_receive {:dispatched, _, %{label: :one}, context}, 1_000
    assert context.plugin_state == saved.state.first
    assert context.state_version == 1
    assert context.source_signal == signal
    assert context.effective_signal == signal
    assert context.turn_context == %{token: :local}
    refute Map.has_key?(context, :agent)
    assert_receive {:dispatched, _, %{label: :two}, ^context}, 1_000
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.completed == 2
  end

  @tag obligation: "jido.agent_server2.I59"
  test "Plugin dispatch failure stops the batch and preserves the successful commit", c do
    for mode <- [:fail, :invalid, :raise, :gate] do
      server = start(c, :ok, directive_timeout: 100)

      assert {:ok, saved, [_, _]} =
               Server.call(server, batch([%Effect{mode: mode}, %Effect{label: :later}]))

      assert_receive {:committed, First, _, _}, 1_000
      assert_receive {:committed, Second, _, _}, 1_000
      assert_receive {:dispatched, task, _, _}, 1_000
      assert_eventually(Server.status(server).phase == :idle)
      assert Server.agent(server) == saved
      assert Server.status(server).last_outcome.status == :succeeded

      assert Server.status(server).last_effect_outcome.status ==
               if(mode == :gate, do: :timed_out, else: :failed)

      refute Process.alive?(task)
      refute_received {:dispatched, _, %{label: :later}, _}
      Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server2.I60"
  test "invalid batches and failed turns do not notify Plugins", c do
    server = start(c)
    before = Server.agent(server)

    assert {:error, _} =
             Server.call(
               server,
               batch([%Effect{}, %Jido.Agent.Directive.StopChild{tag: :unknown}])
             )

    assert {:error, _} = Server.call(server, F.signal(%{mode: :fail}))
    assert Server.agent(server) == before
    refute_received {:committed, _, _, _}
    refute_received {:dispatched, _, _, _}
  end

  @tag obligation: "jido.agent_server2.I57"
  test "commit timeout is finite and supports instance defaults", c do
    for value <- [:infinity, -1, nil, 4_294_967_296] do
      assert {:error, _} =
               Server.start_link(agent: c.agent, runner: c.runner, commit_timeout: value)

      assert {:error, _} = Server.validate_defaults(commit_timeout: value)
    end

    assert :ok = Server.validate_defaults(commit_timeout: 100)
    server = start(c, :ok, commit_timeout: 0)
    assert {:ok, saved, []} = Server.call(server, F.signal())
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.agent(server) == saved
    assert Server.status(server).last_effect_outcome.status == :timed_out
    refute_received {:committed, _, _, _}
  end

  @tag obligation: "jido.agent_server2.I61"
  test "server shutdown stops a blocked commit hook", c do
    server = start(c, :gate)
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert_receive {:committed, First, task, _}, 1_000
    ref = Process.monitor(task)
    :ok = Server.stop(server)
    assert_receive {:DOWN, ^ref, :process, ^task, _}, 1_000
    refute_received {:committed, Second, _, _}
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I61"
  test "callbacks finish linked child work before returning and releasing the next turn", c do
    server = start(c, :linked_child)
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert_receive {:committed, First, callback, _}, 1_000
    assert_receive {:linked_callback_child, child}, 1_000
    callback_ref = Process.monitor(callback)
    child_ref = Process.monitor(child)
    pending = Server.submit(server, F.signal(%{}, "missing"))
    assert {:error, :timeout} = Server.await(pending, 0)
    send(child, :release)
    assert_receive {:DOWN, ^child_ref, :process, ^child, :normal}, 1_000
    assert_receive {:DOWN, ^callback_ref, :process, ^callback, :normal}, 1_000
    assert {:error, _} = Server.await(pending)
    assert_receive {:committed, Second, _, _}, 1_000
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: ["jido.agent_server2.I57", "jido.agent_server2.I61"]
  test "hook timeout stops linked child work while its callback is active", c do
    server = start(c, :linked_child, commit_timeout: 100)
    assert {:ok, saved, []} = Server.call(server, F.signal())
    assert_receive {:committed, First, callback, _}, 1_000
    assert_receive {:linked_callback_child, child}, 1_000
    callback_ref = Process.monitor(callback)
    child_ref = Process.monitor(child)
    assert_receive {:DOWN, ^callback_ref, :process, ^callback, :killed}, 1_000
    assert_receive {:DOWN, ^child_ref, :process, ^child, :killed}, 1_000
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.agent(server) == saved
    assert Server.status(server).last_effect_outcome.status == :timed_out
    refute_received {:committed, Second, _, _}
  end

  @tag obligation: ["jido.agent_server2.I55", "jido.agent_server2.I58"]
  test "callbacks receive the live runtime root", c do
    server = start(c, {:live, :ok})
    :ok = Server.await_ready(server)
    assert {:ok, _, [_]} = Server.call(server, batch([%Effect{}]))
    assert_receive {:runtime_hook, root}, 1_000
    assert Process.alive?(root)
    assert_receive {:runtime_dispatch, ^root}, 1_000
    assert_receive {:dispatched, _, _, %{plugin_state: 7}}, 1_000
    assert_eventually(Server.status(server).phase == :idle)
  end

  @tag obligation: "jido.agent_server2.I57"
  test "a delayed hook result cannot bypass the deadline", c do
    server = start(c, :last_gate, commit_timeout: 100)
    assert {:ok, saved, [_]} = Server.call(server, batch([%Effect{}]))
    assert_receive {:committed, First, _, _}, 1_000
    assert_receive {:committed, Second, task, _}, 1_000
    :ok = :sys.suspend(server)

    try do
      ref = Process.monitor(task)
      send(task, :release)
      assert_receive {:DOWN, ^ref, :process, ^task, :normal}, 1_000
      timer = make_ref()
      Process.send_after(self(), timer, 120)
      assert_receive ^timer, 1_000
    after
      :sys.resume(server)
    end

    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :timed_out
    assert Server.status(server).last_effect_outcome.stage == :after_commit
    assert Server.agent(server) == saved
    refute_received {:committed, Second, _, _}
    refute_received {:dispatched, _, _, _}
  end

  @tag obligation: "jido.agent_server2.I57"
  test "directive budget starts after hooks finish and stale hook timers are ignored", c do
    server = start(c, :last_gate, commit_timeout: 1_000, directive_timeout: 100)
    assert {:ok, _, [_]} = Server.call(server, batch([%Effect{mode: :gate}]))
    assert_receive {:committed, First, _, _}, 1_000
    assert_receive {:committed, Second, task, commit}, 1_000
    timer = make_ref()
    Process.send_after(self(), timer, 120)
    assert_receive ^timer, 1_000
    send(task, :release)
    assert_receive {:dispatched, directive_task, _, _}, 1_000
    send(server, {:commit_timeout, commit.turn_id})
    assert Server.status(server).phase == :running
    send(directive_task, :release)
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: "jido.agent_server2.I61"
  test "owned hooks and Plugin dispatch reject synchronous turn requests", c do
    server = start(c, :probe, name: __MODULE__.Owner)
    assert {:ok, _, [_]} = Server.call(server, batch([%Effect{mode: :probe}]))
    assert_receive {:callback_probe, {:error, :reentrant_turn}}, 1_000
    assert_receive {:callback_probe, {:error, :reentrant_turn}}, 1_000
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: "jido.agent_server2.I57"
  test "instance commit budget is inherited and explicit startup overrides it", c do
    standalone = start(c)
    agent = Server.agent(standalone)
    Server.stop(standalone)
    instance = __MODULE__.Instance
    start_supervised!({Jido, name: instance, agent_server2: [commit_timeout: 0]})
    {:ok, inherited} = Server.start(agent: agent, jido: instance)
    :ok = Server.await_ready(inherited)
    assert {:ok, _, []} = Server.call(inherited, F.signal())
    assert_eventually(Server.status(inherited).phase == :idle)
    assert Server.status(inherited).last_effect_outcome.status == :timed_out
    :ok = Server.stop(inherited)
    {:ok, overridden} = Server.start(agent: agent, jido: instance, commit_timeout: 1_000)
    :ok = Server.await_ready(overridden)
    assert {:ok, _, []} = Server.call(overridden, F.signal())
    assert_receive {:committed, First, _, _}, 1_000
    assert_receive {:committed, Second, _, _}, 1_000
    assert_eventually(Server.status(overridden).phase == :idle)
    assert Server.status(overridden).last_effect_outcome.status == :succeeded
    :ok = Server.stop(overridden)
  end
end
