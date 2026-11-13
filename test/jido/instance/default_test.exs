defmodule Jido.Instance.DefaultTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  setup :ensure_namespace_registry

  alias Jido.AgentServer

  defp ensure_namespace_registry(context),
    do: Jido.Test.Instance.ContractSupport.ensure_namespace_registry(context)

  defmodule DefaultAgent do
    use Jido.Agent, name: "default_instance_agent"
  end

  @removed_root_shortcuts [
    default_instance: [0],
    debug: [0, 1],
    await: [1, 2],
    abandon: [1],
    start_agent: [1],
    stop_agent: [1],
    whereis_agent: [1],
    list_agents: [0],
    agent_count: [0],
    hibernate: [1],
    thaw: [2]
  ]

  setup do
    on_exit(&stop_default_instance/0)
    :ok
  end

  defp stop_default_instance do
    Jido.stop(Jido.Default)
  catch
    :exit, _reason -> :ok
  end

  @tag obligation: ["jido.instance.I1", "jido.instance.I5", "jido.instance.I8"]
  test "Jido does not expose default-instance or AgentServer forwarding shortcuts" do
    Enum.each(@removed_root_shortcuts, fn {name, arities} ->
      Enum.each(arities, fn arity ->
        refute function_exported?(Jido, name, arity)
      end)
    end)
  end

  @tag obligation: "jido.instance.I2"
  test "script startup and shutdown are idempotent", %{jido: jido} do
    name = Module.concat(jido, Script)
    on_exit(fn -> Jido.stop(name) end)
    assert {:ok, pid} = Jido.start(name: name)
    assert {:ok, ^pid} = Jido.start(name: name)
    ref = Process.monitor(pid)
    assert :ok = Jido.stop(name)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert :ok = Jido.stop(name)
  end

  @tag obligation: ["jido.instance.I2", "jido.instance.I4"]
  test "a later start keeps the first namespace and persistence options", %{jido: jido} do
    name = Module.concat(jido, FirstOptions)
    first_namespace = "jido/test/first-options/#{unique_id()}"
    later_namespace = "jido/test/later-options/#{unique_id()}"
    first_persistence = {Jido.Persistence.ETS, table: Module.concat(jido, FirstStore)}
    later_persistence = {Jido.Persistence.ETS, table: Module.concat(jido, LaterStore)}

    pid =
      start_supervised!(%{
        id: name,
        start: {Jido, :start, [[name: name, namespace: first_namespace, persistence: first_persistence]]},
        type: :supervisor
      })

    assert {:ok, ^pid} =
             Jido.start(name: name, namespace: later_namespace, persistence: later_persistence)

    assert Jido.Instance.NamespaceRegistry.namespace(name) == first_namespace

    assert %Jido.Persistence.Config{store: ^first_persistence} =
             Jido.Instance.RuntimeStore.instance_persistence(name)

    assert Jido.Instance.NamespaceRegistry.lookup(later_namespace) == nil
  end

  @tag obligation: "jido.instance.I4"
  test "Telemetry sets and clears debug overrides for the default instance" do
    instance = Jido.Default
    key = {:jido_debug, instance}
    absent = make_ref()
    previous = :persistent_term.get(key, absent)

    on_exit(fn ->
      if previous == absent,
        do: :persistent_term.erase(key),
        else: :persistent_term.put(key, previous)
    end)

    assert instance == Jido.Default
    assert :ok = Jido.Telemetry.set_debug(instance, :on)
    assert Jido.Telemetry.debug_level(instance) == :on
    assert :ok = Jido.Telemetry.set_debug(instance, :verbose)
    assert Jido.Telemetry.debug_status(instance).overrides.semantic_log_mode == :all
    assert :ok = Jido.Telemetry.set_debug(instance, :off)
    assert Jido.Telemetry.debug_level(instance) == :off
  end

  @tag obligation: "jido.instance.I5"
  test "runtime operations use an explicit default instance identity" do
    assert {:ok, _jido} = Jido.start()

    agent = DefaultAgent.instantiate!(id: unique_id("default-agent"))
    agent_id = agent.id
    assert {:ok, server} = Jido.start_agent(Jido.Default, agent)
    assert %Jido.Agent{id: ^agent_id} = AgentServer.snapshot(server).agent
    assert Jido.whereis_agent(Jido.Default, agent_id) == server
    assert Jido.list_agents(Jido.Default) == [{agent_id, server}]
    assert Jido.resident_agent_count(Jido.Default) == 1
    assert :ok = Jido.stop_agent(Jido.Default, agent_id)
    assert Jido.whereis_agent(Jido.Default, agent_id) == nil
  end

  @tag obligation: "jido.instance.I5"
  test "start_agent accepts a module and options with the default instance" do
    assert {:ok, _jido} = Jido.start()

    id = unique_id("default-agent-options")
    assert {:ok, server} = Jido.start_agent(Jido.Default, DefaultAgent, id: id)
    assert %Jido.Agent{id: ^id} = AgentServer.snapshot(server).agent
  end

  @tag obligation: "jido.instance.I2"
  test "the default instance identity owns its runtime names" do
    instance = Jido.Default
    assert Jido.Instance.Names.registry(instance) == Jido.Default.Registry
    assert Jido.Instance.Names.agent_supervisor(instance) == Jido.Default.AgentSupervisor
    assert Jido.Instance.Names.task_supervisor(instance) == Jido.Default.TaskSupervisor
    assert Jido.Instance.Names.runtime_store(instance) == Jido.Default.RuntimeStore

    assert {:ok, _jido} = Jido.start()
  end

  @tag obligation: "jido.instance.I5"
  test "stop and thaw use the explicit default instance identity" do
    table = :"default_lifecycle_#{System.unique_integer([:positive])}"
    persistence = {Jido.Persistence.ETS, table: table}

    assert {:ok, _jido} =
             Jido.start(namespace: "default-persistence-test", persistence: persistence)

    on_exit(fn ->
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end)

    id = unique_id("default-persisted-agent")
    agent = DefaultAgent.instantiate!(id: id)

    assert {:ok, server} = Jido.start_agent(Jido.Default, agent)
    assert :ok = AgentServer.await_ready(server)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = AgentServer.stop(server)
    assert Jido.whereis_agent(Jido.Default, id) == nil

    assert {:ok, restored_server} = Jido.thaw(Jido.Default, DefaultAgent, id)
    assert :ok = AgentServer.await_ready(restored_server)
    assert %Jido.Agent{id: ^id} = AgentServer.snapshot(restored_server).agent
  end
end
