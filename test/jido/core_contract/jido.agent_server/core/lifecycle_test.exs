Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.LifecycleTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule HandoffEffect do
    use Jido.Agent.Directive
    defstruct [:observer]
  end

  defmodule HandoffPlugin do
    use Jido.Plugin
    def directives(_opts), do: [HandoffEffect]

    def dispatch(_runtime, %HandoffEffect{observer: observer}, _context, _opts) do
      send(observer, {:handoff_effect, self()})
      receive do: (:release -> :ok)
    end
  end

  defmodule HandoffBefore do
    use Jido.Action, name: "lifecycle_handoff_before"

    def run(%{count: count}, context),
      do: {:ok, %{count: count}, [%HandoffEffect{observer: context.observer}]}
  end

  defmodule HandoffTarget do
    use Jido.Action,
      name: "lifecycle_handoff_target",
      schema: Zoi.object(%{count: Zoi.integer()})

    def run(%{count: count}, _context), do: {:ok, %{count: count + 1}}
  end

  defmodule HandoffSelector do
    use Jido.Action, name: "lifecycle_handoff_selector"
    def run(input, _context), do: {:handoff, input, HandoffTarget}
  end

  defmodule HandoffFlow do
    use Jido.Flow, name: "lifecycle_handoff_flow"

    flow do
      step "before", action: HandoffBefore, params: %{count: input(:count)}
      handoff "next", selector: HandoffSelector, params: result("before")
      output result("next")
    end
  end

  defmodule HandoffAgent do
    use Jido.Agent, name: "lifecycle_handoff_agent", plugins: [HandoffPlugin]

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "handoff", HandoffFlow
    end
  end

  setup do
    F.setup_runtime()
  end

  @tag obligation: ["jido.agent_server.I2", "jido.agent_server.I17"]
  test "a 90-day Turn rearms bounded timers without changing its deadline", c do
    duration = 90 * 24 * 60 * 60 * 1_000
    assert :ok = Server.validate_defaults(turn_timeout: duration)
    server = F.start(c, turn_timeout: duration)
    turn = F.blocked(server, c.runner)
    {_, %{active: active}} = :sys.get_state(server)
    assert active.deadline > System.monotonic_time(:millisecond) + duration - 5_000
    assert Process.read_timer(active.timer) <= 4_294_967_295

    send(server, {:turn_timeout, turn.id})
    assert %{active: %{turn_id: id}} = Server.status(server)
    assert id == turn.id
    {_, %{active: rearmed}} = :sys.get_state(server)
    assert rearmed.deadline == active.deadline
    assert rearmed.timer != active.timer
    assert Process.read_timer(active.timer) == false
    assert Process.read_timer(rearmed.timer) <= 4_294_967_295

    F.release(turn)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(turn.pending)
    assert Process.read_timer(rearmed.timer) == false
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server.I17", "jido.agent_server.I21"]
  test "Action and Flow timeouts stop work in preparation, execution, and validation", c do
    for type <- ["work", "flow"], stage <- [:preparing, :running, :settling] do
      server = F.start(c, turn_timeout: 200)
      input = if stage == :running, do: %{mode: :gate}, else: %{stage: stage, observer: self()}
      pending = Server.submit(server, F.signal(input, type), context: %{observer: self()})
      blocked = gate(stage)
      assert Server.agent(server) === c.agent
      assert {:error, :turn_timeout} = Server.await(pending, 1_000)
      F.down(blocked)
      F.unchanged(server, c.agent)
      F.clean(c.runner)
      Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server.I17"
  test "zero timeout cannot commit; infinity permits a blocked turn", c do
    zero = F.start(c, turn_timeout: 0)
    assert {:error, :turn_timeout} = Server.call(zero, F.signal())
    F.unchanged(zero, c.agent)
    infinite = F.start(c, turn_timeout: :infinity)
    turn = F.blocked(infinite, c.runner)
    assert {:error, :timeout} = Server.await(turn.pending, 0)
    F.release(turn)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(turn.pending, 1_000)
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server.I18", "jido.agent_server.I19", "jido.agent_server.I21"]
  test "cancellation preserves state at each lifecycle stage and permits later work", c do
    for type <- ["work", "flow"], stage <- [:preparing, :running, :settling] do
      server = F.start(c, turn_timeout: :infinity)
      input = if stage == :running, do: %{mode: :gate}, else: %{stage: stage, observer: self()}
      pending = Server.submit(server, F.signal(input, type), context: %{observer: self()})
      blocked = gate(stage)
      assert %{active: %{turn_id: id}} = Server.status(server)
      assert :ok = Server.cancel_turn(server, id)
      assert {:error, :cancelled} = Server.await(pending, 1_000)
      F.down(blocked)
      F.unchanged(server, c.agent)
      F.clean(c.runner)
      assert {:ok, %{state: %{count: 1}}, []} = Server.call(server, F.signal())
      Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server.I18"
  test "cancellation owns a Handoff chain after predecessor commit", c do
    {:ok, server} = Jido.start_agent(c.jido, HandoffAgent, id: unique_id("handoff-cancel"))
    assert :ok = Server.await_ready(server)

    request = Jido.Signal.new!("handoff", %{count: 2}, source: "/test")
    pending = Server.submit(server, request, context: %{observer: self()})
    assert_receive {:handoff_effect, effect}, 1_000
    effect_monitor = Process.monitor(effect)

    assert :ok = Server.cancel(server)
    assert {:error, :cancelled} = Server.await(pending)
    assert_receive {:DOWN, ^effect_monitor, :process, ^effect, _reason}, 1_000
    assert Process.alive?(server)
  end

  @tag obligation: ["jido.agent_server.I18", "jido.agent_server.I19", "jido.agent_server.I24"]
  test "stale IDs and late messages cannot affect a newer turn", c do
    server = F.start(c)
    assert {:error, :not_running} = Server.cancel(server)
    old = F.blocked(server, c.runner)
    assert :ok = Server.cancel_turn(server, old.id)
    assert {:error, :cancelled} = Server.await(old.pending, 1_000)
    current = F.blocked(server, c.runner)
    refute current.id == old.id
    assert {:error, :stale_turn} = Server.cancel_turn(server, old.id)
    send(server, {:turn_timeout, old.id})
    send(server, {:worker_complete, old.id})
    send(server, {make_ref(), {:ok, %{count: 999}, []}})
    assert %{active: %{turn_id: id}, state_version: 0} = Server.status(server)
    assert id == current.id
    F.release(current)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(current.pending, 1_000)
    assert %{state_version: 1, active: nil} = Server.status(server)
    F.clean(c.runner)
  end

  @tag obligation: [
         "jido.agent_server.I5",
         "jido.agent_server.I11",
         "jido.agent_server.I18",
         "jido.agent_server.I21"
       ]
  test "cancellation wait timeout does not revoke cleanup; repeated requests share it", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    supervisor = Module.concat(c.runner, WorkerSupervisor)
    :ok = :sys.suspend(supervisor)

    try do
      caller = Task.async(fn -> catch_exit(Server.cancel(server, 30)) end)
      assert_eventually(Server.status(server).active.stage == :cleaning)
      assert {:timeout, _} = Task.await(caller)
      assert Server.agent(server) === c.agent
      waiters = for _ <- 1..2, do: Task.async(fn -> Server.cancel_turn(server, turn.id) end)
      assert %{state_version: 0, active: %{stage: :cleaning}} = Server.status(server)
      :ok = :sys.resume(supervisor)
      for waiter <- waiters, do: assert(:ok == Task.await(waiter))
      assert {:error, :cancelled} = Server.await(turn.pending, 1_000)
      F.down(turn.action)
      F.down(turn.worker)
      F.unchanged(server, c.agent)
      F.clean(c.runner)
    after
      :sys.resume(supervisor)
    end
  end

  @tag obligation: ["jido.agent_server.I17", "jido.agent_server.I18", "jido.agent_server.I21"]
  test "startup abort fences in-flight Worker creation before queued work", c do
    for reason <- [:cancel, :timeout] do
      server = F.start(c, turn_timeout: if(reason == :cancel, do: :infinity, else: 200))
      supervisor = Module.concat(c.runner, WorkerSupervisor)
      :ok = :sys.suspend(supervisor)

      try do
        pending = Server.submit(server, F.signal(), context: %{observer: self()})
        assert_eventually(Server.status(server).active.stage == :starting)
        waiter = if reason == :cancel, do: Task.async(fn -> Server.cancel(server) end)
        assert_eventually(Server.status(server).active.stage == :cleaning)
        assert Server.agent(server) === c.agent
        assert {:error, :timeout} = Server.await(pending, 0)
        queued = Server.submit(server, F.signal(%{mode: :gate}), context: %{observer: self()})
        assert %{admission: %{postponed: 1}} = Server.status(server)
        :ok = :sys.resume(supervisor)
        if waiter, do: assert(:ok == Task.await(waiter))
        expected = if reason == :cancel, do: :cancelled, else: :turn_timeout
        assert {:error, ^expected} = Server.await(pending, 1_000)
        assert_receive {:executing, action, _, %{mode: :gate}}, 1_000
        refute_received {:executing, _, _, %{amount: 1}}
        send(action, :release)
        assert {:ok, %{state: %{count: 1}}, []} = Server.await(queued, 1_000)
        assert %{state_version: 1} = Server.status(server)
        F.clean(c.runner)
      after
        :sys.resume(supervisor)
        if Process.alive?(server), do: Server.stop(server)
      end
    end
  end

  @tag obligation: ["jido.agent_server.I17", "jido.agent_server.I18", "jido.agent_server.I21"]
  test "first abort reason wins while cleanup is blocked", c do
    for first <- [:timeout, :cancel] do
      server = F.start(c, turn_timeout: 200)
      turn = F.blocked(server, c.runner)
      supervisor = Module.concat(c.runner, WorkerSupervisor)
      :ok = :sys.suspend(supervisor)

      try do
        waiter = if first == :cancel, do: Task.async(fn -> Server.cancel(server) end)
        assert_eventually(Server.status(server).active.stage == :cleaning)

        if first == :cancel do
          F.elapsed(220)
        else
          waiter2 = Task.async(fn -> Server.cancel(server) end)
          Process.put(:extra_cancel, waiter2)
        end

        :ok = :sys.resume(supervisor)
        if waiter, do: assert(:ok == Task.await(waiter))
        if extra = Process.delete(:extra_cancel), do: assert(:ok == Task.await(extra))
        expected = if first == :cancel, do: :cancelled, else: :turn_timeout
        assert {:error, ^expected} = Server.await(turn.pending, 1_000)
        F.unchanged(server, c.agent)
        F.clean(c.runner)
      after
        :sys.resume(supervisor)
        if Process.alive?(server), do: Server.stop(server)
      end
    end
  end

  @tag obligation: "jido.agent_server.I22"
  test "explicit stop confirms that the server is down", c do
    server = F.start(c)
    ref = Process.monitor(server)
    assert :ok = Server.stop(server, :shutdown, 500)
    assert_receive {:DOWN, ^ref, :process, ^server, :shutdown}, 500
    refute Process.alive?(server)
  end

  @tag obligation: "jido.agent_server.I22"
  test "explicit stop and abrupt server death stop owned execution", c do
    for mode <- [:stop, :kill] do
      server = F.start(c)
      turn = F.blocked(server, c.runner)
      if mode == :stop, do: Server.stop(server, :user_stop), else: Process.exit(server, :kill)
      F.down(server)
      F.down(turn.action)
      F.down(turn.worker)
      assert {:error, _} = Server.await(turn.pending, 1_000)
      F.clean(c.runner)
    end
  end

  @tag obligation: "jido.agent_server.I23"
  test "lost Worker or lifecycle task stops the activation and queued work", c do
    for loss <- [:worker, :lifecycle] do
      server = F.start(c)
      input = if loss == :worker, do: %{mode: :gate}, else: %{stage: :preparing, observer: self()}
      pending = Server.submit(server, F.signal(input), context: %{observer: self()})
      blocked = gate(if(loss == :worker, do: :running, else: :preparing))
      queued = Server.submit(server, F.signal(), context: %{observer: self()})
      assert %{admission: %{postponed: 1}} = Server.status(server)
      target = if loss == :worker, do: Server.status(server).active.worker_pid, else: blocked
      Process.exit(target, :kill)
      assert {:error, _} = Server.await(pending, 1_000)
      F.down(server)
      F.down(blocked)
      assert {:error, _} = Server.await(queued, 1_000)
      refute_received {:executing, _, _, _}
      F.clean(c.runner)
    end
  end

  @tag obligation: "jido.agent_server.I23"
  test "Runner loss stops an idle activation", c do
    server = F.start(c)
    assert :ok = stop_supervised(Runic.Runner)
    F.down(server)
  end

  @tag obligation: "jido.agent_server.I23"
  test "unconfirmed cleanup stops activation without starting queued work", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    supervisor = Module.concat(c.runner, WorkerSupervisor)
    :ok = :sys.suspend(supervisor)

    try do
      waiter = Task.async(fn -> Server.cancel(server) end)
      assert_eventually(Server.status(server).active.stage == :cleaning)
      queued = Server.submit(server, F.signal(), context: %{observer: self()})
      assert %{admission: %{postponed: 1}} = Server.status(server)
      Process.exit(turn.worker, :kill)
      F.down(turn.worker)
      :ok = :sys.resume(supervisor)
      assert {:error, _} = Task.await(waiter)
      assert {:error, _} = Server.await(turn.pending, 1_000)
      F.down(server)
      F.down(turn.action)
      assert {:error, _} = Server.await(queued, 1_000)
      refute_received {:executing, _, _, _}
      F.clean(c.runner)
    after
      :sys.resume(supervisor)
    end
  end

  @tag obligation: ["jido.agent_server.I7", "jido.agent_server.I18", "jido.agent_server.I20"]
  test "completion and cancellation races commit at most once and release execution", c do
    server = F.start(c)

    Enum.reduce(1..10, 0, fn _, committed ->
      turn = F.blocked(server, c.runner)
      cancel = Task.async(fn -> Server.cancel_turn(server, turn.id) end)
      F.release(turn)
      result = Server.await(turn.pending, 1_000)
      cancelled = Task.await(cancel)

      next =
        case result do
          {:ok, %{state: %{count: count}}, []} ->
            assert count == committed + 1
            assert cancelled in [:ok, {:error, :not_running}]
            committed + 1

          {:error, :cancelled} ->
            assert cancelled == :ok
            committed
        end

      assert Server.agent(server).state.count == next
      assert Server.status(server).state_version == next
      F.clean(c.runner)
      next
    end)
  end

  defp gate(:running) do
    assert_receive {:executing, action, _context, _}, 1_000
    action
  end

  defp gate(stage) do
    assert_receive {:lifecycle_gate, ^stage, task}, 1_000
    # Validation gates follow an already completed Action.
    if stage == :settling, do: assert_receive({:executing, _, _, _}, 1_000)
    task
  end
end
