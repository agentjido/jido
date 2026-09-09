defmodule Jido.RuntimeTopologyTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.AgentServer.{PluginChild, SpawnRegistry}
  alias Jido.RuntimeStore

  alias JidoTest.AgentRuntimeFixtures.{
    ChildAgent,
    PluginRuntimeAgent
  }

  @moduletag capture_log: true

  test "an instance owns five isolated standard services", %{jido: jido, jido_pid: jido_pid} do
    assert standard_children(jido_pid) == expected_children(jido)

    other = :"#{jido}_other"
    other_pid = start_supervised!({Jido, name: other}, id: other)

    assert standard_children(other_pid) == expected_children(other)

    first_pids = jido |> service_names() |> Enum.map(&Process.whereis/1) |> MapSet.new()
    other_pids = other |> service_names() |> Enum.map(&Process.whereis/1) |> MapSet.new()

    assert Enum.all?(first_pids, &is_pid/1)
    assert Enum.all?(other_pids, &is_pid/1)
    assert MapSet.disjoint?(first_pids, other_pids)
  end

  test "each standard service can be replaced without restarting its siblings", %{
    jido: base_jido
  } do
    for index <- 0..4 do
      jido = :"#{base_jido}_restart_#{index}"
      jido_pid = start_supervised!({Jido, name: jido}, id: jido)
      {target, child_id} = Enum.at(services(jido), index)
      assert :ok = RuntimeStore.put(jido, :topology_test, :checkpoint, :retained)
      before = service_pids(jido)
      old_pid = Map.fetch!(before, target)
      ref = Process.monitor(old_pid)
      assert :ok = Supervisor.terminate_child(jido_pid, child_id)
      assert_receive {:DOWN, ^ref, :process, ^old_pid, :shutdown}, 2_000

      for {name, sibling_pid} <- before, name != target do
        assert Process.whereis(name) == sibling_pid,
               "#{inspect(name)} stopped when #{inspect(target)} stopped"
      end

      assert {:ok, replacement} = Supervisor.restart_child(jido_pid, child_id)
      refute replacement == old_pid

      after_restart =
        eventually(
          fn ->
            current = service_pids(jido)

            if is_pid(current[target]) and current[target] != old_pid,
              do: current
          end,
          timeout: 2_000
        )

      for {name, sibling_pid} <- before, name != target do
        assert after_restart[name] == sibling_pid,
               "#{inspect(name)} restarted when #{inspect(target)} failed"
      end

      assert Process.whereis(jido) == jido_pid
      assert Process.whereis(Jido.runtime_store_name(jido))
      assert RuntimeStore.fetch(jido, :topology_test, :checkpoint) == {:ok, :retained}

      assert :ok = stop_supervised!(jido)
    end
  end

  test "max_tasks limits only the Task Supervisor pool", %{jido: base_jido} do
    jido = :"#{base_jido}_bounded"
    start_supervised!({Jido, name: jido, max_tasks: 1}, id: jido)
    task_supervisor = Jido.task_supervisor_name(jido)
    gate = make_ref()

    assert {:ok, task} =
             Task.Supervisor.start_child(task_supervisor, fn ->
               receive do
                 {:release, ^gate} -> :ok
               end
             end)

    assert {:error, :max_children} = Task.Supervisor.start_child(task_supervisor, fn -> :ok end)

    assert {:ok, agent} =
             Jido.start_agent(jido, ChildAgent,
               id: unique_id("capacity-agent"),
               restart: :temporary
             )

    assert Process.alive?(agent)
    assert agent in direct_child_pids(Jido.agent_supervisor_name(jido))
    send(task, {:release, gate})
  end

  test "Agent Servers and Plugin wrappers are peers in one runtime pool", %{jido: jido} do
    assert AgentServer.child_spec(agent: ChildAgent, jido: jido).restart == :transient
    assert AgentServer.child_spec(agent: ChildAgent).restart == :temporary

    {:ok, server} =
      Jido.start_agent(jido, PluginRuntimeAgent,
        id: unique_id("plugin-topology"),
        restart: :temporary
      )

    {_phase, state} = :sys.get_state(server)
    child = state.children[{:plugin, JidoTest.AgentRuntimeFixtures.BootPlugin}]
    direct_children = direct_child_pids(Jido.agent_supervisor_name(jido))

    assert server in direct_children
    assert child.lifecycle_pid in direct_children
    refute child.pid in direct_children

    wrapper_state = :sys.get_state(child.lifecycle_pid)
    assert wrapper_state.owner == server
    assert [{_, root, _, _}] = Supervisor.which_children(wrapper_state.supervisor)
    assert root == child.pid
    assert PluginChild.child_pid(child.lifecycle_pid) == child.pid
  end

  test "a full instance stop removes live runtime state and does not discover durable Agents", %{
    jido: base_jido
  } do
    jido = :"#{base_jido}_generation"
    table = :"#{base_jido}_persistence"
    persistence = {Jido.Persistence.ETS, table: table}
    jido_pid = start_supervised!({Jido, name: jido, persistence: persistence}, id: jido)
    id = unique_id("durable-topology")

    {:ok, server} =
      Jido.start_agent(jido, PluginRuntimeAgent, id: id, restart: :temporary)

    {_phase, state} = :sys.get_state(server)
    plugin = state.children[{:plugin, JidoTest.AgentRuntimeFixtures.BootPlugin}]

    assert :ok = RuntimeStore.put(jido, :topology_test, :generation, 1)

    processes = [jido_pid, server, plugin.lifecycle_pid, plugin.pid]
    refs = for pid <- processes, do: {Process.monitor(pid), pid}

    assert :ok = stop_supervised!(jido)

    for {ref, pid} <- refs do
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
    end

    assert :ets.whereis(Jido.runtime_store_name(jido)) == :undefined

    replacement = start_supervised!({Jido, name: jido, persistence: persistence}, id: jido)
    refute replacement == jido_pid
    assert Jido.list_agents(jido) == []
    assert RuntimeStore.fetch(jido, :topology_test, :generation) == :error

    assert {:ok, restored} = Jido.thaw(jido, PluginRuntimeAgent, id)
    assert Process.alive?(restored)
  end

  defp expected_children(jido) do
    %{
      Jido.task_supervisor_name(jido) => {:supervisor, [Task.Supervisor]},
      Jido.registry_name(jido) => {:supervisor, [Registry]},
      Jido.runtime_store_name(jido) => {:worker, [RuntimeStore]},
      SpawnRegistry => {:worker, [SpawnRegistry]},
      Jido.agent_supervisor_name(jido) => {:supervisor, [DynamicSupervisor]}
    }
  end

  defp standard_children(jido_pid) do
    Map.new(Supervisor.which_children(jido_pid), fn {id, pid, type, modules} ->
      assert is_pid(pid)
      {id, {type, modules}}
    end)
  end

  defp service_names(jido) do
    Enum.map(services(jido), &elem(&1, 0))
  end

  defp services(jido) do
    [
      {Jido.task_supervisor_name(jido), Jido.task_supervisor_name(jido)},
      {Jido.registry_name(jido), Jido.registry_name(jido)},
      {Jido.runtime_store_name(jido), Jido.runtime_store_name(jido)},
      {SpawnRegistry.name(jido), SpawnRegistry},
      {Jido.agent_supervisor_name(jido), Jido.agent_supervisor_name(jido)}
    ]
  end

  defp service_pids(jido) do
    Map.new(service_names(jido), &{&1, Process.whereis(&1)})
  end

  defp direct_child_pids(supervisor) do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(supervisor),
        is_pid(pid),
        do: pid
  end
end
