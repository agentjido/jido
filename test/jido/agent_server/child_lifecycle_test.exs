defmodule Jido.AgentServer.ChildLifecycleTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ParentRef
  alias Jido.Signal

  alias JidoTest.AgentRuntimeFixtures.{
    ChildAgent,
    RuntimeAgent
  }

  defp eventually_agent(server, predicate, timeout \\ 3_000) do
    eventually(
      fn ->
        agent = Server.agent(server)
        if predicate.(agent), do: agent
      end,
      timeout: timeout
    )
  end

  test "spawns, addresses, and stops a child Agent without putting runtime refs in state", %{
    jido: jido
  } do
    parent_id = unique_id("parent")
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: parent_id)

    spawn = Directive.spawn_agent(ChildAgent, :worker, meta: %{role: :worker})

    assert {:ok, agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{event: :spawned, directive: spawn})
             )

    assert agent.state.events == [:spawned]
    refute Map.has_key?(agent.state, :children)
    refute Map.has_key?(agent.state, :parent)

    children =
      eventually(fn ->
        case Server.children(parent) do
          %{worker: child} -> child
          _children -> nil
        end
      end)

    assert children.id == "#{parent_id}/worker"
    assert children.meta == %{role: :worker}
    assert Jido.whereis_agent(jido, children.id) == children.pid

    child_signal = Signal.new!("child.record", %{event: :from_parent}, source: "/test")

    assert {:ok, _parent_agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :sent_to_child,
                 directive: Directive.emit_to_child(:worker, child_signal)
               })
             )

    eventually_agent(children.pid, &(&1.state.events == [:from_parent]))

    monitor = Process.monitor(children.pid)
    assert :ok = Server.stop_child(parent, :worker)
    assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 2_000
    refute Map.has_key?(Server.children(parent), :worker)
  end

  test "a child sends a domain result to its parent as a later Signal", %{jido: jido} do
    parent_id = unique_id("reply-parent")
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: parent_id)

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :spawned,
                 directive: Directive.spawn_agent(ChildAgent, :worker)
               })
             )

    child = eventually(fn -> Server.children(parent)[:worker] end)
    reply = Signal.new!("runtime.record", %{event: :child_result}, source: "/child")

    assert {:ok, child_agent} =
             Server.call(
               child.pid,
               signal("child.reply", %{event: :worked, reply: reply})
             )

    assert child_agent.state.events == [:worked]

    parent_agent = eventually_agent(parent, &(:child_result in &1.state.events))
    assert :child_result in parent_agent.state.events
  end

  test "compensates a child start when relationship persistence fails", %{
    jido: jido,
    jido_pid: jido_pid
  } do
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("compensate-parent"))
    {:idle, state} = :sys.get_state(parent)
    child_id = unique_id("compensated-child")
    runtime_store = Jido.runtime_store_name(jido)

    assert :ok = Supervisor.terminate_child(jido_pid, runtime_store)

    source = signal("runtime.directive")

    context = %Jido.AgentServer.DirectiveContext{
      agent_id: state.agent.id,
      source_signal: source,
      signal: source
    }

    directive = Directive.spawn_agent(ChildAgent, :worker, opts: %{id: child_id})

    assert {:error, {:spawn_agent_failed, {:relationship_persist_failed, :not_running}}, ^state} =
             Jido.AgentServer.DirectiveRuntime.handle(directive, context, state)

    eventually(fn -> Jido.whereis_agent(jido, child_id) == nil end)
    assert {:ok, _pid} = Supervisor.restart_child(jido_pid, runtime_store)
  end

  test "parent death policy uses private runtime state", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("death-parent"))

    parent_ref =
      ParentRef.new!(pid: parent, id: Server.agent(parent).id, tag: :owner, meta: %{})

    {:ok, child} =
      Jido.start_agent(jido, ChildAgent,
        id: unique_id("death-child"),
        parent: parent_ref,
        on_parent_death: :emit_orphan
      )

    assert :ok = Jido.stop_agent(jido, parent)

    agent = eventually_agent(child, &(&1.state.events != []))
    assert [%{parent_id: _id, tag: :owner}] = agent.state.events
    refute Map.has_key?(agent.state, :__parent__)
    assert Server.status(child).runtime.parent == nil
  end

  test "a transient child does not restart after its parent stops", %{jido: jido} do
    parent_id = unique_id("transient-parent")
    child_id = "#{parent_id}/worker"
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: parent_id)

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :spawned,
                 directive: Directive.spawn_agent(ChildAgent, :worker)
               })
             )

    child = eventually(fn -> Server.children(parent)[:worker] end)
    monitor = Process.monitor(child.pid)

    assert :ok = Jido.stop_agent(jido, parent)

    assert_receive {:DOWN, ^monitor, :process, _pid, {:shutdown, {:parent_down, :shutdown}}},
                   2_000

    eventually(fn -> Jido.whereis_agent(jido, child_id) == nil end)
  end

  test "a parent tracks the new PID after an abnormal child restart", %{jido: jido} do
    parent_id = unique_id("restart-parent")
    child_id = "#{parent_id}/worker"
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: parent_id)

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :spawned,
                 directive: Directive.spawn_agent(ChildAgent, :worker, restart: :transient)
               })
             )

    original = eventually(fn -> Server.children(parent)[:worker] end)
    monitor = Process.monitor(original.pid)
    Process.exit(original.pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, _pid, :killed}, 2_000

    restarted =
      eventually(fn ->
        case Server.children(parent)[:worker] do
          %{pid: pid} = child when pid != original.pid -> child
          _child -> nil
        end
      end)

    assert Process.alive?(restarted.pid)
    assert restarted.id == child_id
    assert Jido.whereis_agent(jido, child_id) == restarted.pid

    assert {:ok, binding} = Jido.agent_parent_binding(jido, child_id)
    assert binding.parent_id == parent_id
    assert binding.tag == :worker
  end

  test "an adopted child restores its parent binding after an abnormal restart", %{jido: jido} do
    parent_id = unique_id("adopt-restart-parent")
    child_id = unique_id("adopt-restart-child")
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: parent_id)
    {:ok, child} = Jido.start_agent(jido, ChildAgent, id: child_id)

    assert :ok = Server.adopt_child(parent, child, :adopted, %{role: :worker})
    assert Server.status(child).runtime.parent.id == parent_id

    monitor = Process.monitor(child)
    Process.exit(child, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^child, :killed}, 2_000

    restarted =
      eventually(fn ->
        case Jido.whereis_agent(jido, child_id) do
          pid when is_pid(pid) and pid != child -> pid
          _pid -> nil
        end
      end)

    tracked =
      eventually(fn ->
        case Server.children(parent)[:adopted] do
          %{pid: ^restarted} = info -> info
          _info -> nil
        end
      end)

    assert tracked.meta == %{role: :worker}
    assert Server.status(restarted).runtime.parent.id == parent_id
  end
end
