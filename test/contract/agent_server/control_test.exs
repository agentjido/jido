Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.ControlTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  alias JidoTest.Persistence.ProbeStore

  defmodule Storage do
    @behaviour Jido.Persistence.Adapter
    def get(key, opts), do: ProbeStore.get(key, opts)

    def compare_and_swap(key, expected, value, opts) do
      case Elixir.Agent.get(opts[:control], & &1) do
        :gate ->
          send(opts[:observer], {:saving, self()})
          receive do: (:release -> ProbeStore.compare_and_swap(key, expected, value, opts))

        :probe ->
          server = opts[:server].()

          send(
            opts[:observer],
            {:storage_probe, Server.quiesce(server), Server.hibernate(server),
             Server.resume(server), Server.stop(server)}
          )

          ProbeStore.compare_and_swap(key, expected, value, opts)

        :ok ->
          ProbeStore.compare_and_swap(key, expected, value, opts)

        error ->
          error
      end
    end
  end

  defmodule Probe do
    use Jido.Action, name: "server2_control_probe"

    def run(_, context) do
      server = context.server

      run = fn ->
        [
          Server.quiesce(server),
          Server.resume(server),
          Server.hibernate(server),
          Server.stop(server)
        ]
      end

      send(context.observer, {:control_probe, run.(), Task.async(run) |> Task.await(1_000)})
      {:ok, context.agent_state}
    end
  end

  defmodule ShutdownResource do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      Process.flag(:trap_exit, true)
      {:ok, init}
    end

    def terminate(_, init) do
      send(init.options[:observer], {:closing, self()})
      receive do: (:release -> :ok)
    end
  end

  defmodule ShutdownPlugin do
    use Jido.Plugin
    def child_spec(init), do: %{start: {ShutdownResource, :start_link, [init]}, shutdown: 5_000}
  end

  setup do
    store = start_supervised!(ProbeStore)
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    Map.merge(F.setup_runtime(), %{store: store, control: control, observer: observer})
  end

  defp persistent(c, opts \\ []) do
    source =
      {Storage,
       [
         store: c.store,
         control: c.control,
         observer: self(),
         server: fn ->
           Server.whereis(c.jido, c.agent.id)
         end
       ]}

    server =
      F.start(
        c,
        Keyword.merge(
          [jido: c.jido, runner: Jido.exec_runner_name(c.jido), persistence: source],
          opts
        )
      )

    assert :ok = Server.await_ready(server)
    {server, source}
  end

  defp mode(c, value), do: Elixir.Agent.update(c.control, fn _ -> value end)

  defp closed(server) do
    eventually(fn -> Server.status(server).admission.mode == :quiescing end)
  end

  defp replacement(root, old) do
    eventually(fn ->
      pid = Server.Activation.worker(root)
      if is_pid(pid) and pid != old, do: pid
    end)
  end

  @tag obligation: "jido.agent_server2.I84"
  test "quiesce rejects queued turns, keeps reads, and does not replay on resume", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    queued = Server.submit(server, F.signal())
    assert Server.status(server).admission.postponed == 1
    control = Task.async(fn -> Server.quiesce(server) end)
    closed(server)
    {_, %{control: %{token: token}}} = :sys.get_state(server)
    assert {:error, :quiesced} = Server.await(queued, 1_000)
    assert {:error, :quiesced} = Server.call(server, F.signal())
    assert Server.agent(server) == c.agent
    assert {:error, :not_quiescent} = Server.resume(server)
    assert nil == Task.yield(control, 0)
    F.release(turn)
    assert {:ok, _, _} = Server.await(turn.pending, 1_000)
    assert :ok = Task.await(control)
    assert %{mode: :quiesced, postponed: 0} = Server.status(server).admission
    assert :ok = Server.resume(server)
    send(server, {:control_timeout, token})
    assert Server.status(server).admission.mode == :open
    assert {:ok, agent, _} = Server.call(server, F.signal())
    assert agent.state.count == 2
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I85"
  test "cancel quiesce confirms pre-commit cleanup without changing state", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    action_ref = Process.monitor(turn.action)
    assert :ok = Server.quiesce(server, active: :cancel)
    assert_receive {:DOWN, ^action_ref, :process, _, _}, 1_000
    assert {:error, :cancelled} = Server.await(turn.pending)
    assert Server.agent(server) == c.agent
    assert Server.status(server).admission.mode == :quiesced
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I85"
  test "cancel policy waits for an accepted durable commit", c do
    {server, _} = persistent(c)
    mode(c, :gate)
    pending = Server.submit(server, F.signal())
    assert_receive {:saving, task}, 1_000
    control = Task.async(fn -> Server.quiesce(server, active: :cancel) end)
    closed(server)
    assert {:error, :commit_in_progress} = Server.cancel(server)
    assert nil == Task.yield(control, 0)
    send(task, :release)
    assert {:ok, agent, _} = Server.await(pending)
    assert agent.state.count == 1
    assert :ok = Task.await(control)
    assert Server.status(server).state_version == 1
  end

  @tag obligation: "jido.agent_server2.I85"
  test "quiescence waits for post-commit effects", c do
    observer = self()

    handler = fn _, _ ->
      send(observer, {:effect, self()})
      receive do: (:release -> :ok)
    end

    server = F.start(c, directive_handler: handler)
    assert {:ok, _, _} = Server.call(server, F.signal(%{mode: :directive}))
    assert_receive {:effect, effect}, 1_000
    control = Task.async(fn -> Server.quiesce(server, active: :cancel) end)
    closed(server)
    assert nil == Task.yield(control, 0)
    assert Server.status(server).active.stage == :effects
    send(effect, :release)
    assert :ok = Task.await(control)
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: "jido.agent_server2.I86"
  test "timeout leaves admission closed until settled and rejects concurrent controls", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    control = Task.async(fn -> Server.quiesce(server, timeout: 80) end)
    closed(server)
    assert {:error, :control_in_progress} = Server.quiesce(server)
    assert {:error, :quiesce_timeout} = Task.await(control)
    assert {:error, :not_quiescent} = Server.resume(server)
    assert {:error, :quiesced} = Server.call(server, F.signal())
    F.release(turn)
    assert {:ok, _, _} = Server.await(turn.pending)
    eventually(fn -> Server.status(server).admission.mode == :quiesced end)
    assert :ok = Server.resume(server)
  end

  @tag obligation: "jido.agent_server2.I87"
  test "owned callbacks and nested tasks reject synchronous control", c do
    agent =
      Jido.Agent.define!(
        name: "control_probe",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [{"work", Probe}]
      )
      |> Jido.Agent.instantiate!()

    server = F.start(c, agent: agent)

    assert {:ok, _, _} =
             Server.call(server, F.signal(), context: %{server: server, observer: self()})

    expected = List.duplicate({:error, :reentrant_turn}, 4)
    assert_receive {:control_probe, ^expected, ^expected}, 1_000
  end

  @tag obligation: "jido.agent_server2.I88"
  test "closed admission and owners survive worker recovery without control replay", c do
    root = F.start_activation(c)
    server = Server.Activation.worker(root)
    assert :ok = Server.attach(server)
    assert :ok = Server.quiesce(server)
    Process.exit(server, :kill)
    new = replacement(root, server)
    assert :ok = Server.await_ready(new)
    assert Server.status(new).owners == [self()]
    assert Server.status(new).admission.mode == :quiesced
    assert {:error, :quiesced} = Server.call(new, F.signal())
    assert :ok = Server.resume(new)
    assert {:ok, _, _} = Server.call(new, F.signal())
  end

  @tag obligation: "jido.agent_server2.I89"
  test "owner attachment is idempotent and detach releases its monitor", c do
    server = F.start(c)
    assert :ok = Server.attach(server)
    assert :ok = Server.attach(server)
    assert Server.status(server).owners == [self()]
    {:monitors, monitors} = Process.info(server, :monitors)
    assert Enum.count(monitors, &(&1 == {:process, self()})) == 1
    assert :ok = Server.detach(server)
    assert :ok = Server.detach(server)
    assert Server.status(server).owners == []
    {:monitors, monitors} = Process.info(server, :monitors)
    refute {:process, self()} in monitors
  end

  @tag obligation: "jido.agent_server2.I89"
  test "attached owner prevents idle stop and DOWN starts the budget", c do
    server = F.start(c, idle_timeout: 40)
    root = Server.activation(server)
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    assert :ok = Server.attach(server, owner)
    F.elapsed(80)
    assert Process.alive?(root)
    send(owner, :stop)
    F.down(root)
  end

  @tag obligation: "jido.agent_server2.I90"
  test "touch resets idle time and stale expiry does not stop the activation", c do
    server = F.start(c, idle_timeout: 1_000)
    {:idle, data} = :sys.get_state(server)
    {_, old_token} = data.idle_timer
    assert :ok = Server.touch(server)
    send(server, {:idle_timeout, old_token})
    assert Server.status(server).phase == :idle
    assert Process.alive?(server)
    {:idle, next} = :sys.get_state(server)
    refute next.idle_timer == data.idle_timer
  end

  @tag obligation: "jido.agent_server2.I90"
  test "idle budget starts after active work and effects settle", c do
    observer = self()

    handler = fn _, _ ->
      send(observer, {:effect, self()})
      receive do: (:release -> :ok)
    end

    server = F.start(c, idle_timeout: 40, directive_handler: handler)
    root = Server.activation(server)
    turn = F.blocked(server, c.runner)
    F.elapsed(80)
    assert Process.alive?(root)
    F.release(turn)
    assert {:ok, _, _} = Server.await(turn.pending)
    assert :ok = Server.attach(server)
    assert {:ok, _, _} = Server.call(server, F.signal(%{mode: :directive}))
    assert_receive {:effect, effect}, 1_000
    assert :ok = Server.detach(server)
    F.elapsed(80)
    assert Process.alive?(root)
    send(effect, :release)
    F.down(root)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I91"
  test "hibernate saves settled revision, confirms activation exit, and restores", c do
    {server, source} = persistent(c)
    root = Server.activation(server)
    assert {:ok, committed, _} = Server.call(server, F.signal())
    assert :ok = Server.hibernate(server)
    refute Process.alive?(root)
    refute Process.alive?(server)

    restored =
      F.start(c,
        jido: c.jido,
        runner: Jido.exec_runner_name(c.jido),
        persistence: source,
        persistence_mode: :restore
      )

    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored) == committed
    assert Server.status(restored).state_version == 1
  end

  @tag obligation: "jido.agent_server2.I91"
  test "hibernate rejects queued turns and keeps reads during save", c do
    {server, _} = persistent(c)
    mode(c, :gate)
    task = Task.async(fn -> Server.hibernate(server) end)
    assert_receive {:saving, saver}, 1_000
    assert Server.agent(server) == c.agent
    assert Server.status(server).admission.mode == :quiescing
    assert {:error, :quiesced} = Server.call(server, F.signal())
    assert {:error, :not_quiescent} = Server.resume(server)
    assert nil == Task.yield(task, 0)
    send(saver, :release)
    assert :ok = Task.await(task)
  end

  @tag obligation: "jido.agent_server2.I92"
  test "known save rejection retains live state and restores prior admission", c do
    {server, _} = persistent(c)
    mode(c, {:error, {:rejected, :disk_full}})

    assert {:error, %{reason: {:rejected, :disk_full}, resumable?: true}} =
             Server.hibernate(server)

    assert Process.alive?(server)
    assert Server.status(server).admission.mode == :open
    assert :ok = Server.quiesce(server)
    assert {:error, %{resumable?: true}} = Server.hibernate(server)
    assert Server.status(server).admission.mode == :quiesced
    mode(c, :ok)
    assert :ok = Server.resume(server)
    assert {:ok, _, _} = Server.call(server, F.signal())
  end

  @tag obligation: "jido.agent_server2.I92"
  test "uncertain or conflicting save blocks resume and survives recovery", c do
    for reason <- [:indeterminate, :conflict] do
      {server, _} = persistent(c, agent: %{c.agent | id: "blocked-#{reason}"})
      root = Server.activation(server)
      mode(c, {:error, reason})
      assert {:error, %{reason: ^reason, resumable?: false}} = Server.hibernate(server)
      assert Process.alive?(server)
      assert {:error, :unsafe_resume} = Server.resume(server)
      assert {:error, :quiesced} = Server.call(server, F.signal())
      mode(c, :ok)
      Process.exit(server, :kill)
      new = replacement(root, server)
      assert :ok = Server.await_ready(new)
      assert Server.status(new).admission.mode == :blocked
      assert {:error, :unsafe_resume} = Server.resume(new)
      assert :ok = Server.stop(new)
    end
  end

  @tag obligation: "jido.agent_server2.I92"
  test "save deadline kills owned task and leaves a live blocked Agent", c do
    {server, _} = persistent(c)
    mode(c, :gate)
    pending = Task.async(fn -> Server.hibernate(server, timeout: 80) end)
    assert_receive {:saving, saver}, 1_000
    monitor = Process.monitor(saver)
    assert {:error, %{reason: :indeterminate, resumable?: false}} = Task.await(pending)
    assert_receive {:DOWN, ^monitor, :process, ^saver, _}, 1_000
    assert Process.alive?(server)
    assert {:error, :unsafe_resume} = Server.resume(server)
  end

  @tag obligation: "jido.agent_server2.I93"
  test "idle stop does not save and idle hibernate uses save-and-stop", c do
    {server, _} = persistent(c, idle_timeout: 80)
    root = Server.activation(server)
    mode(c, {:error, :indeterminate})
    F.down(root)
    mode(c, :ok)

    {server, _} =
      persistent(c,
        agent: %{c.agent | id: "idle-save"},
        idle_timeout: 80,
        idle_policy: :hibernate
      )

    root = Server.activation(server)
    mode(c, :gate)
    assert_receive {:saving, saver}, 1_000
    assert Process.alive?(root)
    send(saver, :release)
    F.down(root)
  end

  @tag obligation: "jido.agent_server2.I93"
  test "failed automatic save closes admission without automatic retries", c do
    {server, _} = persistent(c, idle_timeout: 40, idle_policy: :hibernate)
    mode(c, {:error, {:rejected, :disk_full}})
    eventually(fn -> Server.status(server).admission.mode == :quiesced end)
    {:idle, data} = :sys.get_state(server)
    assert data.idle_timer == nil
    assert data.control == nil
    assert :ok = Server.resume(server)
  end

  @tag obligation: "jido.agent_server2.I94"
  test "validates control and idle settings and keeps default expiry disabled", c do
    server = F.start(c)
    assert Server.status(server).idle_timeout == :infinity

    assert {:error, %{reason: :persistence_not_configured, resumable?: true}} =
             Server.hibernate(server)

    for opts <- [[active: :other], [timeout: :infinity], [timeout: -1], [typo: 1], :bad] do
      assert {:error, _} = Server.quiesce(server, opts)
      assert {:error, _} = Server.hibernate(server, opts)
    end

    assert {:error, _} = Server.attach(server, :bad)
    assert {:error, _} = Server.detach(server, :bad)

    for opts <- [[idle_timeout: -1], [idle_policy: :other], [idle_policy: :hibernate]] do
      assert {:error, _} =
               Server.start_link(Keyword.merge([agent: c.agent, runner: c.runner], opts))
    end
  end

  @tag obligation: "jido.agent_server2.I87"
  test "storage callbacks cannot synchronously control their owner", c do
    {server, _} = persistent(c)
    mode(c, :probe)
    assert :ok = Server.hibernate(server)
    error = {:error, :reentrant_turn}
    assert_receive {:storage_probe, ^error, ^error, ^error, ^error}, 1_000
  end

  @tag obligation: "jido.agent_server2.I88"
  test "interrupted quiesce recovers closed after execution cleanup", c do
    root = F.start_activation(c)
    server = Server.Activation.worker(root)
    turn = F.blocked(server, c.runner)

    pending =
      Task.async(fn ->
        try do
          Server.quiesce(server)
        catch
          :exit, reason -> {:lost, reason}
        end
      end)

    closed(server)
    Process.exit(server, :kill)
    assert {:lost, _} = Task.await(pending)
    new = replacement(root, server)
    assert :ok = Server.await_ready(new)
    eventually(fn -> Server.status(new).admission.mode == :quiesced end)
    assert :ok = Server.resume(new)
    assert Server.agent(new) == c.agent
    assert {:error, _} = Server.await(turn.pending)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I92"
  test "worker death during save retains blocked admission", c do
    {server, _} = persistent(c)
    root = Server.activation(server)
    mode(c, :gate)

    pending =
      Task.async(fn ->
        try do
          Server.hibernate(server)
        catch
          :exit, reason -> {:lost, reason}
        end
      end)

    assert_receive {:saving, saver}, 1_000
    ref = Process.monitor(saver)
    Process.exit(server, :kill)
    assert {:lost, _} = Task.await(pending)
    assert_receive {:DOWN, ^ref, :process, ^saver, _}, 1_000
    mode(c, :ok)
    new = replacement(root, server)
    assert :ok = Server.await_ready(new)
    assert Server.status(new).admission.mode == :blocked
    assert {:error, :unsafe_resume} = Server.resume(new)
  end

  @tag obligation: "jido.agent_server2.I92"
  test "save budget is bounded by persistence_timeout", c do
    {server, _} = persistent(c, persistence_timeout: 80)
    mode(c, :gate)
    pending = Task.async(fn -> Server.hibernate(server, timeout: 5_000) end)
    assert_receive {:saving, saver}, 1_000
    ref = Process.monitor(saver)
    assert {:error, %{reason: :indeterminate, resumable?: false}} = Task.await(pending, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^saver, _}, 1_000
  end

  @tag obligation: "jido.agent_server2.I94"
  test "idle settings inherit instance defaults with startup override", c do
    instance = Module.concat(__MODULE__, "Defaults#{System.unique_integer([:positive])}")

    start_supervised!(
      {Jido, name: instance, namespace: "control-defaults", agent_server: [idle_timeout: 1_000]}
    )

    {:ok, server} = Server.start(agent: c.agent, jido: instance)
    assert Server.status(server).idle_timeout == 1_000

    {:ok, other} =
      Server.start(agent: %{c.agent | id: "override"}, jido: instance, idle_timeout: :infinity)

    assert Server.status(other).idle_timeout == :infinity
  end

  @tag obligation: "jido.agent_server2.I91"
  test "hibernate success waits for Plugin shutdown and root DOWN", c do
    agent =
      Jido.Agent.define!(
        name: "shutdown_control",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugins: [{ShutdownPlugin, observer: c.observer}],
        routes: [{"work", F.Work}]
      )
      |> Jido.Agent.instantiate!()

    {server, _} = persistent(c, agent: agent)
    root = Server.activation(server)
    task = Task.async(fn -> Server.hibernate(server) end)
    assert_receive {:closing, resource}, 1_000

    try do
      assert Process.alive?(root)
      assert nil == Task.yield(task, 0)
    after
      send(resource, :release)
    end

    assert :ok = Task.await(task)
    refute Process.alive?(root)
    refute Process.alive?(resource)
  end

  @tag obligation: "jido.agent_server2.I92"
  test "loss of the save task keeps the Agent live and blocked", c do
    {server, _} = persistent(c)
    mode(c, :gate)
    task = Task.async(fn -> Server.hibernate(server) end)
    assert_receive {:saving, saver}, 1_000
    Process.exit(saver, :kill)
    assert {:error, %{reason: :indeterminate, resumable?: false}} = Task.await(task)
    assert Process.alive?(server)
    assert Server.status(server).admission.mode == :blocked
    assert {:error, :unsafe_resume} = Server.resume(server)
  end

  @tag obligation: "jido.agent_server2.I94"
  test "initializing workers reject controls before readiness", c do
    mode(c, :gate)
    source = {Storage, store: c.store, control: c.control, observer: self()}
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido), persistence: source)
    assert_receive {:saving, task}, 1_000
    assert {:error, :not_ready} = Server.quiesce(server)
    assert {:error, :not_ready} = Server.resume(server)
    assert {:error, :not_ready} = Server.hibernate(server)
    send(task, :release)
    assert :ok = Server.await_ready(server)
  end

  @tag obligation: "jido.agent_server2.I89"
  test "owner DOWN handling does not consume the Runner lifecycle monitor", c do
    server = F.start(c)
    root = Server.activation(server)
    runner = Process.whereis(c.runner)
    assert :ok = Server.attach(server, runner)
    Process.exit(runner, :kill)
    F.down(root)
  end

  @tag obligation: "jido.agent_server2.I86"
  test "unresponsive servers cannot leave control callers waiting forever", c do
    server = F.start(c)
    :ok = :sys.suspend(server)

    try do
      task =
        Task.async(fn ->
          try do
            Server.quiesce(server, timeout: 20)
          catch
            :exit, reason -> {:caller_exit, reason}
          end
        end)

      assert {:caller_exit, {:timeout, _}} = Task.await(task, 2_000)
    after
      :sys.resume(server)
    end
  end
end
