Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.ActivationControlTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.activation", async: false

  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  defp closed(server) do
    eventually(fn -> Server.status(server).admission.mode == :quiescing end)
  end

  defp replacement(root, old) do
    eventually(fn ->
      pid = Server.Supervisor.worker(root)
      if is_pid(pid) and pid != old, do: pid
    end)
  end

  @tag obligation: "jido.agent_server.activation.I9"
  test "closed admission and owners survive worker recovery without control replay", c do
    root = F.start_activation(c)
    server = Server.Supervisor.worker(root)
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

  @tag obligation: "jido.agent_server.activation.I9"
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

  @tag obligation: ["jido.agent_server.activation.I9", "jido.agent_server.activation.I10"]
  test "an attached owner prevents idle stop and owner loss starts the budget", c do
    server = F.start(c, idle_timeout: 40)
    root = Server.activation(server)
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    assert :ok = Server.attach(server, owner)
    F.elapsed(80)
    assert Process.alive?(root)
    send(owner, :stop)
    F.down(root)
  end

  @tag obligation: "jido.agent_server.activation.I10"
  test "touch resets idle time and a stale expiry is inert", c do
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

  @tag obligation: "jido.agent_server.activation.I10"
  test "the idle budget starts after active work and effects settle", c do
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

  @tag obligation: "jido.agent_server.activation.I9"
  test "interrupted quiesce recovers closed after execution cleanup", c do
    root = F.start_activation(c)
    server = Server.Supervisor.worker(root)
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

  @tag obligation: "jido.agent_server.activation.I9"
  test "owner loss handling does not consume the Runner lifecycle monitor", c do
    server = F.start(c)
    root = Server.activation(server)
    runner = Process.whereis(c.runner)
    assert :ok = Server.attach(server, runner)
    Process.exit(runner, :kill)
    F.down(root)
  end
end
