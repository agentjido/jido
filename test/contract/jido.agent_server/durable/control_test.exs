Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Durable.ControlTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.durable", async: false

  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  alias JidoTest.Persistence.ProbeStore

  setup do
    store = start_supervised!(ProbeStore)
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)
    Map.merge(F.setup_runtime(), %{store: store, control: control, observer: observer})
  end

  @tag obligation: "jido.agent_server.durable.I1"
  test "persistent control requires explicit valid persistence settings", c do
    server = F.start(c)

    assert {:error, %{reason: :persistence_not_configured, resumable?: true}} =
             Server.hibernate(server)

    for persistence <- [nil, false] do
      assert {:error, _} =
               Server.start_link(
                 agent: c.agent,
                 runner: c.runner,
                 persistence: persistence,
                 idle_policy: :hibernate
               )
    end
  end

  @tag obligation: "jido.agent_server.durable.I9"
  test "hibernate saves settled revision, confirms activation exit, and restores", c do
    {server, source} = F.persistent(c)
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

  @tag obligation: "jido.agent_server.durable.I9"
  test "hibernate rejects queued turns and keeps reads during save", c do
    {server, _} = F.persistent(c)
    F.storage_mode(c, :gate)
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

  @tag obligation: "jido.agent_server.durable.I9"
  test "known save rejection retains live state and restores prior admission", c do
    {server, _} = F.persistent(c)
    F.storage_mode(c, {:error, {:rejected, :disk_full}})

    assert {:error, %{reason: {:rejected, :disk_full}, resumable?: true}} =
             Server.hibernate(server)

    assert Process.alive?(server)
    assert Server.status(server).admission.mode == :open
    assert :ok = Server.quiesce(server)
    assert {:error, %{resumable?: true}} = Server.hibernate(server)
    assert Server.status(server).admission.mode == :quiesced
    F.storage_mode(c, :ok)
    assert :ok = Server.resume(server)
    assert {:ok, _, _} = Server.call(server, F.signal())
  end

  @tag obligation: "jido.agent_server.durable.I9"
  test "uncertain or conflicting save blocks resume and survives recovery", c do
    for {reason, index} <-
          Enum.with_index([:indeterminate, {:indeterminate, :lost_reply}, :conflict]) do
      {server, _} = F.persistent(c, agent: %{c.agent | id: "blocked-#{index}"})
      root = Server.activation(server)
      F.storage_mode(c, {:error, reason})
      assert {:error, %{reason: ^reason, resumable?: false}} = Server.hibernate(server)
      assert Process.alive?(server)
      assert {:error, :unsafe_resume} = Server.resume(server)
      assert {:error, :quiesced} = Server.call(server, F.signal())
      F.storage_mode(c, :ok)
      Process.exit(server, :kill)
      new = F.replacement(root, server)
      assert :ok = Server.await_ready(new)
      assert Server.status(new).admission.mode == :blocked
      assert {:error, :unsafe_resume} = Server.resume(new)
      assert :ok = Server.stop(new)
    end
  end

  @tag obligation: "jido.agent_server.durable.I9"
  test "save deadline kills owned task and leaves a live blocked Agent", c do
    {server, _} = F.persistent(c)
    F.storage_mode(c, :gate)
    pending = Task.async(fn -> Server.hibernate(server, timeout: 80) end)
    assert_receive {:saving, saver}, 1_000
    monitor = Process.monitor(saver)
    assert {:error, %{reason: :indeterminate, resumable?: false}} = Task.await(pending)
    assert_receive {:DOWN, ^monitor, :process, ^saver, _}, 1_000
    assert Process.alive?(server)
    assert {:error, :unsafe_resume} = Server.resume(server)
  end

  @tag obligation: "jido.agent_server.durable.I10"
  test "idle hibernate uses the same save-and-stop boundary", c do
    {server, _} =
      F.persistent(c,
        agent: %{c.agent | id: "idle-save"},
        idle_timeout: 80,
        idle_policy: :hibernate
      )

    root = Server.activation(server)
    F.storage_mode(c, :gate)
    assert_receive {:saving, saver}, 1_000
    assert Process.alive?(root)
    send(saver, :release)
    F.down(root)
  end

  @tag obligation: "jido.agent_server.durable.I10"
  test "failed automatic save closes admission without automatic retries", c do
    {server, _} = F.persistent(c, idle_timeout: 40, idle_policy: :hibernate)
    F.storage_mode(c, {:error, {:rejected, :disk_full}})
    eventually(fn -> Server.status(server).admission.mode == :quiesced end)
    {:idle, data} = :sys.get_state(server)
    assert data.idle_timer == nil
    assert data.control == nil
    assert :ok = Server.resume(server)
  end

  @tag obligation: "jido.agent_server.durable.I9"
  test "worker death during save retains blocked admission", c do
    {server, _} = F.persistent(c)
    root = Server.activation(server)
    F.storage_mode(c, :gate)

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
    F.storage_mode(c, :ok)
    new = F.replacement(root, server)
    assert :ok = Server.await_ready(new)
    assert Server.status(new).admission.mode == :blocked
    assert {:error, :unsafe_resume} = Server.resume(new)
  end

  @tag obligation: "jido.agent_server.durable.I9"
  test "save budget is bounded by persistence_timeout", c do
    {server, _} = F.persistent(c, persistence_timeout: 80)
    F.storage_mode(c, :gate)
    pending = Task.async(fn -> Server.hibernate(server, timeout: 5_000) end)
    assert_receive {:saving, saver}, 1_000
    ref = Process.monitor(saver)
    assert {:error, %{reason: :indeterminate, resumable?: false}} = Task.await(pending, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^saver, _}, 1_000
  end

  @tag obligation: "jido.agent_server.durable.I9"
  test "hibernate success waits for Plugin shutdown and root DOWN", c do
    agent =
      Jido.Agent.define!(%{
        name: "shutdown_control",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugins: [
          %{
            id: F.ShutdownPlugin.id(),
            provider: F.ShutdownPlugin,
            vsn: F.ShutdownPlugin.vsn(),
            data: %{observer: c.observer}
          }
        ],
        routes: [
          %{
            path: "work",
            handler: %{kind: :action, target: F.Work},
            state: %{source: :output, path: []}
          }
        ]
      })
      |> Jido.Agent.instantiate!(id: Jido.Signal.ID.generate!())

    {server, _} = F.persistent(c, agent: agent)
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

  @tag obligation: "jido.agent_server.durable.I9"
  test "loss of the save task keeps the Agent live and blocked", c do
    {server, _} = F.persistent(c)
    F.storage_mode(c, :gate)
    task = Task.async(fn -> Server.hibernate(server) end)
    assert_receive {:saving, saver}, 1_000
    Process.exit(saver, :kill)
    assert {:error, %{reason: :indeterminate, resumable?: false}} = Task.await(task)
    assert Process.alive?(server)
    assert Server.status(server).admission.mode == :blocked
    assert {:error, :unsafe_resume} = Server.resume(server)
  end
end
