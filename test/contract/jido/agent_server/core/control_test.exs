Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.ControlTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server", async: false

  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Core
  alias JidoTest.AgentServer.Fixtures, as: F
  alias JidoTest.Persistence.ProbeStore

  defmodule Probe do
    use Jido.Action, name: "server_control_probe"

    def run(_, context) do
      server = context.server

      run = fn ->
        [
          Server.quiesce(server, timeout: 100),
          Server.resume(server, 100),
          Server.hibernate(server, timeout: 100),
          Server.stop(server, :shutdown, 100)
        ]
      end

      send(context.observer, {:control_probe, run.(), Task.async(run) |> Task.await(1_000)})
      {:ok, context.agent_state}
    end
  end

  setup do
    store = start_supervised!(ProbeStore)
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    Map.merge(F.setup_runtime(), %{store: store, control: control, observer: observer})
  end

  @tag obligation: "jido.agent_server.I84"
  test "quiesce rejects queued turns, keeps reads, and does not replay on resume", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    queued = Server.submit(server, F.signal())
    assert Server.status(server).admission.postponed == 1
    control = Task.async(fn -> Server.quiesce(server, timeout: 1_000) end)
    F.closed(server)
    {_, %{control: %{token: token}}} = :sys.get_state(server)
    assert {:error, :quiesced} = Server.await(queued, 1_000)
    assert {:error, :quiesced} = Server.call(server, F.signal(), timeout: 100)
    assert Server.agent(server) == c.agent
    assert {:error, :not_quiescent} = Server.resume(server)
    assert nil == Task.yield(control, 0)
    F.release(turn)
    assert {:ok, _, _} = Server.await(turn.pending, 1_000)
    assert :ok = Task.await(control, 1_500)
    assert %{mode: :quiesced, postponed: 0} = Server.status(server).admission
    assert :ok = Server.resume(server)
    send(server, {:control_timeout, token})
    assert Server.status(server).admission.mode == :open
    assert {:ok, agent, _} = Server.call(server, F.signal())
    assert agent.state.count == 2
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I85"
  test "cancel quiesce confirms pre-commit cleanup without changing state", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    action_ref = Process.monitor(turn.action)
    assert :ok = Server.quiesce(server, active: :cancel, timeout: 500)
    assert_receive {:DOWN, ^action_ref, :process, _, _}, 1_000
    assert {:error, :cancelled} = Server.await(turn.pending)
    assert Server.agent(server) == c.agent
    assert Server.status(server).admission.mode == :quiesced
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I85"
  test "cancel policy waits for an accepted durable commit", c do
    {server, _} = F.persistent(c)
    F.storage_mode(c, :gate)
    pending = Server.submit(server, F.signal())
    assert_receive {:saving, task}, 1_000
    control = Task.async(fn -> Server.quiesce(server, active: :cancel, timeout: 1_000) end)
    F.closed(server)
    assert {:error, :commit_in_progress} = Server.cancel(server)
    assert nil == Task.yield(control, 0)
    send(task, :release)
    assert {:ok, agent, _} = Server.await(pending)
    assert agent.state.count == 1
    assert :ok = Task.await(control, 1_500)
    assert Server.status(server).state_version == 1
  end

  @tag obligation: "jido.agent_server.I85"
  test "quiescence waits for post-commit effects", c do
    observer = self()

    handler = fn _, _ ->
      send(observer, {:effect, self()})
      receive do: (:release -> :ok)
    end

    server = F.start(c, directive_handler: handler)
    assert {:ok, _, _} = Server.call(server, F.signal(%{mode: :directive}))
    assert_receive {:effect, effect}, 1_000
    control = Task.async(fn -> Server.quiesce(server, active: :cancel, timeout: 1_000) end)
    F.closed(server)
    assert nil == Task.yield(control, 0)
    assert Server.status(server).active.stage == :effects
    send(effect, :release)
    assert :ok = Task.await(control, 1_500)
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: "jido.agent_server.I86"
  test "timeout leaves admission closed until settled and rejects concurrent controls", c do
    server = F.start(c)
    turn = F.blocked(server, c.runner)
    control = Task.async(fn -> Server.quiesce(server, timeout: 80) end)
    F.closed(server)
    assert {:error, :control_in_progress} = Server.quiesce(server)
    assert {:error, :quiesce_timeout} = Task.await(control, 1_000)
    assert {:error, :not_quiescent} = Server.resume(server)
    assert {:error, :quiesced} = Server.call(server, F.signal())
    F.release(turn)
    assert {:ok, _, _} = Server.await(turn.pending)
    eventually(fn -> Server.status(server).admission.mode == :quiesced end)
    assert :ok = Server.resume(server)
  end

  @tag obligation: "jido.agent_server.I87"
  test "owned callbacks and nested tasks reject synchronous control", c do
    agent =
      Jido.Agent.define!(%{
        name: "control_probe",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        routes: [%{path: "work", handler: %{kind: :action, target: Probe}}]
      })
      |> Jido.Agent.instantiate!(id: Jido.Signal.ID.generate!())

    server = F.start(c, agent: agent)

    assert {:ok, _, _} =
             Server.call(server, F.signal(), context: %{server: server, observer: self()})

    expected = List.duplicate({:error, :reentrant_turn}, 4)
    assert_receive {:control_probe, ^expected, ^expected}, 1_000
  end

  @tag obligation: "jido.agent_server.I94"
  test "validates control and idle settings and keeps default expiry disabled", c do
    server = F.start(c)
    assert Server.status(server).idle_timeout == :infinity

    for opts <- [[active: :other], [timeout: :infinity], [timeout: -1], [typo: 1], :bad] do
      assert {:error, _} = Server.quiesce(server, opts)
      assert {:error, _} = Server.hibernate(server, opts)
    end

    assert {:error, _} = Server.attach(server, :bad)
    assert {:error, _} = Server.detach(server, :bad)

    for opts <- [[idle_timeout: -1], [idle_policy: :other]] do
      assert {:error, _} =
               Server.start_link(Keyword.merge([agent: c.agent, runner: c.runner], opts))
    end

    assert {:error, %{message: "invalid control options"}} =
             Core.control_options([{:active, :finish} | :invalid])

    assert Core.control_options([]) == {:ok, :finish, 5_000}
    assert Core.control_options(active: :cancel, timeout: 7) == {:ok, :cancel, 7}
    assert Core.control_wait(5_000) == 6_000
    assert Core.control_wait(4_294_967_295) == 4_294_967_295
  end

  @tag obligation: "jido.agent_server.I87"
  test "storage callbacks cannot synchronously control their owner", c do
    {server, _} = F.persistent(c)
    F.storage_mode(c, :probe)
    assert :ok = Server.hibernate(server, timeout: 1_000)
    error = {:error, :reentrant_turn}
    assert_receive {:storage_probe, ^error, ^error, ^error, ^error}, 1_000
  end

  @tag obligation: "jido.agent_server.I94"
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

  @tag obligation: "jido.agent_server.I94"
  test "initializing workers reject controls before readiness", c do
    F.storage_mode(c, :gate)
    source = {F.ControlStorage, store: c.store, control: c.control, observer: self()}
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido), persistence: source)
    assert_receive {:saving, task}, 1_000
    assert {:error, :not_ready} = Server.quiesce(server)
    assert {:error, :not_ready} = Server.resume(server)
    assert {:error, :not_ready} = Server.hibernate(server)
    send(task, :release)
    assert :ok = Server.await_ready(server)
  end

  @tag obligation: "jido.agent_server.I86"
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
