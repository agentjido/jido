defmodule Jido.InstanceHelpersTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer

  defmodule DefaultAgent do
    use Jido.Agent, name: "default_instance_agent"
  end

  setup do
    on_exit(&stop_default_instance/0)
    :ok
  end

  defp stop_default_instance do
    Jido.stop()
  catch
    :exit, _reason -> :ok
  end

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

  test "default debug helpers set and clear the default instance overrides" do
    instance = Jido.default_instance()
    key = {:jido_debug, instance}
    absent = make_ref()
    previous = :persistent_term.get(key, absent)

    on_exit(fn ->
      if previous == absent,
        do: :persistent_term.erase(key),
        else: :persistent_term.put(key, previous)
    end)

    assert instance == Jido.Default
    assert :ok = Jido.debug(:on)
    assert Jido.debug() == :on
    assert :ok = Jido.debug(:verbose, redact: false)
    assert Jido.Debug.override(instance, :redact_sensitive) == false
    assert :ok = Jido.debug(:off)
    assert Jido.debug() == :off
  end

  test "start_agent uses the default instance when no instance is given" do
    assert {:ok, _jido} = Jido.start()

    agent = DefaultAgent.new!(id: unique_id("default-agent"))
    agent_id = agent.id
    assert {:ok, server} = Jido.start_agent(agent)
    assert %Jido.Agent{id: ^agent_id} = AgentServer.agent(server)
    assert Jido.whereis_agent(agent_id) == server
    assert Jido.list_agents() == [{agent_id, server}]
    assert Jido.agent_count() == 1
    assert :ok = Jido.stop_agent(agent_id)
    assert Jido.whereis_agent(agent_id) == nil
  end

  test "start_agent accepts a module and options for the default instance" do
    assert {:ok, _jido} = Jido.start()

    id = unique_id("default-agent-options")
    assert {:ok, server} = Jido.start_agent(DefaultAgent, id: id)
    assert %Jido.Agent{id: ^id} = AgentServer.agent(server)
  end

  test "default instance helpers cover runtime names and parent bindings" do
    assert Jido.registry_name() == Jido.registry_name(Jido.default_instance())
    assert Jido.agent_supervisor_name() == Jido.agent_supervisor_name(Jido.default_instance())
    assert Jido.task_supervisor_name() == Jido.task_supervisor_name(Jido.default_instance())
    assert Jido.runtime_store_name() == Jido.runtime_store_name(Jido.default_instance())

    assert {:ok, _jido} = Jido.start()

    binding = %{parent_id: "parent", tag: :child, meta: %{}}

    assert :ok =
             Jido.RuntimeStore.put(
               Jido.default_instance(),
               :agent_relationships,
               "child",
               binding
             )

    assert {:ok, %{parent_id: "parent", parent_partition: nil, tag: :child, meta: %{}}} =
             Jido.agent_parent_binding("child")
  end

  test "hibernate and thaw use the default instance when no instance is given" do
    assert {:ok, _jido} = Jido.start()

    table = :"default_lifecycle_#{System.unique_integer([:positive])}"
    persistence = {Jido.Persistence.ETS, table: table}

    on_exit(fn ->
      if :ets.whereis(table) != :undefined, do: :ets.delete(table)
    end)

    id = unique_id("default-persisted-agent")
    agent = DefaultAgent.new!(id: id)

    assert {:ok, server} = Jido.start_agent(agent, persistence: persistence)
    assert :ok = Jido.hibernate(server)
    assert Jido.whereis_agent(id) == nil

    assert {:ok, restored_server} = Jido.thaw(DefaultAgent, id, persistence: persistence)
    assert %Jido.Agent{id: ^id} = AgentServer.agent(restored_server)
  end

  test "invalid parent bindings are rejected and missing metadata is normalized", %{jido: jido} do
    for binding <- [:invalid, %{parent_id: 42, tag: :child}] do
      assert :ok = Jido.RuntimeStore.put(jido, :agent_relationships, "child", binding)
      assert :error = Jido.agent_parent_binding(jido, "child")
    end

    binding = %{parent_id: "parent", tag: :child, meta: :invalid}
    assert :ok = Jido.RuntimeStore.put(jido, :agent_relationships, "child", binding)

    assert {:ok, %{parent_id: "parent", parent_partition: nil, tag: :child, meta: %{}}} =
             Jido.agent_parent_binding(jido, "child")

    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert {:error, :not_found} = Jido.stop_agent(jido, pid)
  end
end
