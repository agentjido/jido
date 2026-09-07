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

  alias JidoTest.AgentServerRuntimeFixtures.OwnedExecutionAgent

  defmodule BlockingDispatchPlugin do
    use Jido.Plugin

    @impl true
    def prepare_dispatch(_runtime, signal, _context, _opts) do
      case signal.data do
        %{prepare_gate: gate, observer: observer} ->
          send(observer, {:signal_preparation_blocked, gate, self()})

          receive do
            {:release_signal_preparation, ^gate} -> {:ok, signal}
          end

        _data ->
          {:ok, signal}
      end
    end
  end

  defmodule CompatibleFactory do
    def new(opts), do: ChildAgent.new(opts)
  end

  defmodule IgnoringFactory do
    def new(_opts), do: ChildAgent.new(id: "factory-ignored-request")
  end

  defmodule ParentCancellationExec do
    defdelegate run_async(executable, input, context, opts), to: Jido.Exec
    defdelegate handle_message(handle, message), to: Jido.Exec
    def cancel(_handle), do: {:error, :parent_cancel_failed}
  end

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

  test "an asynchronously prepared child target uses the restarted child PID", %{jido: jido} do
    definition = %{RuntimeAgent.agent() | plugins: [BlockingDispatchPlugin]}
    {:ok, parent} = Jido.start_agent(jido, definition, id: unique_id("target-parent"))

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :spawned,
                 directive: Directive.spawn_agent(ChildAgent, :worker, restart: :transient)
               })
             )

    child = eventually(fn -> Server.children(parent)[:worker] end)
    gate = make_ref()

    outbound =
      Signal.new!(
        "child.record",
        %{event: :after_restart, prepare_gate: gate, observer: self()},
        source: "/test"
      )

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :prepared,
                 directive: Directive.emit_to_child(:worker, outbound)
               })
             )

    assert_receive {:signal_preparation_blocked, ^gate, worker}, 2_000
    original_ref = Process.monitor(child.pid)
    Process.exit(child.pid, :kill)
    assert_receive {:DOWN, ^original_ref, :process, _pid, :killed}, 2_000

    restarted =
      eventually(fn ->
        case Server.children(parent)[:worker] do
          %{pid: pid} = info when pid != child.pid -> info
          _info -> nil
        end
      end)

    send(worker, {:release_signal_preparation, gate})
    eventually_agent(restarted.pid, &(:after_restart in &1.state.events))
  end

  test "an asynchronously prepared parent target observes parent loss", %{jido: jido} do
    observer = self()
    definition = %{ChildAgent.agent() | plugins: [BlockingDispatchPlugin]}
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("target-parent"))

    parent_ref =
      ParentRef.new!(pid: parent, id: Server.agent(parent).id, tag: :owner, meta: %{})

    policy = fn reason, outcome ->
      send(observer, {:relative_dispatch_failed, reason, outcome})
      :continue
    end

    {:ok, child} =
      Jido.start_agent(jido, definition,
        id: unique_id("target-child"),
        parent: parent_ref,
        on_parent_death: :continue,
        error_policy: policy
      )

    gate = make_ref()

    reply =
      Signal.new!(
        "runtime.record",
        %{event: :must_not_arrive, prepare_gate: gate, observer: observer},
        source: "/test"
      )

    assert {:ok, _agent} =
             Server.call(child, signal("child.reply", %{event: :prepared, reply: reply}))

    assert_receive {:signal_preparation_blocked, ^gate, worker}, 2_000
    assert :ok = Jido.stop_agent(jido, parent)
    eventually(fn -> Server.status(child).runtime.parent == nil end)
    send(worker, {:release_signal_preparation, gate})

    assert_receive {:relative_dispatch_failed, :no_parent, outcome}, 2_000
    assert outcome.committed?
    assert Server.status(child).phase == :idle
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

  test "child factories must preserve requested identity before tracking", %{jido: jido} do
    observer = self()

    policy = fn reason, outcome ->
      send(observer, {:factory_spawn_failed, reason, outcome})
      :continue
    end

    {:ok, parent} =
      Jido.start_agent(jido, RuntimeAgent,
        id: unique_id("factory-parent"),
        error_policy: policy
      )

    requested_id = unique_id("factory-child")

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :invalid_factory,
                 directive:
                   Directive.spawn_agent(IgnoringFactory, :invalid,
                     opts: %{id: requested_id, partition: :blue}
                   )
               })
             )

    assert_receive {:factory_spawn_failed,
                    {:spawn_agent_failed,
                     %Jido.Error.ValidationError{
                       message: "Agent Server Agent constructor ignored the requested id"
                     }}, outcome},
                   2_000

    assert outcome.committed?
    refute Map.has_key?(Server.children(parent), :invalid)
    assert Jido.whereis_agent(jido, requested_id, partition: :blue) == nil
    assert Jido.whereis_agent(jido, "factory-ignored-request", partition: :blue) == nil

    assert {:ok, _agent} =
             Server.call(
               parent,
               signal("runtime.directive", %{
                 event: :valid_factory,
                 directive:
                   Directive.spawn_agent(CompatibleFactory, :valid,
                     opts: %{id: requested_id, partition: :blue}
                   )
               })
             )

    child = eventually(fn -> Server.children(parent)[:valid] end)
    assert child.id == requested_id
    assert child.partition == :blue
    assert child.module == ChildAgent
    assert Jido.whereis_agent(jido, requested_id, partition: :blue) == child.pid
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

  test "parent death preserves an indeterminate custom cancellation reason", %{jido: jido} do
    {:ok, parent} =
      Jido.start_agent(jido, RuntimeAgent,
        id: unique_id("cancel-parent"),
        restart: :temporary
      )

    parent_ref =
      ParentRef.new!(pid: parent, id: Server.agent(parent).id, tag: :owner, meta: %{})

    {:ok, child} =
      Jido.start_agent(jido, OwnedExecutionAgent,
        id: unique_id("cancel-child"),
        parent: parent_ref,
        on_parent_death: :stop,
        exec_module: ParentCancellationExec,
        restart: :temporary
      )

    gate = make_ref()
    observer = self()

    caller =
      Task.async(fn ->
        Server.call(
          child,
          signal("owned.action", %{test: observer, gate: gate, label: :parent_cancel})
        )
      end)

    assert_receive {:owned_execution, :parent_cancel, worker}, 2_000
    worker_ref = Process.monitor(worker)
    child_ref = Process.monitor(child)
    assert :ok = Jido.stop_agent(jido, parent)

    error = {:parent_down, {:cancellation_failed, :parent_cancel_failed}}
    assert {:error, ^error} = Task.await(caller, 2_000)
    assert_receive {:DOWN, ^child_ref, :process, ^child, {:shutdown, ^error}}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
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

  for policy <- [:stop, :continue, :emit_orphan], termination <- [:normal, :kill] do
    test "a permanent child cannot restart after a #{termination} parent death under #{policy}",
         %{
           jido: jido
         } do
      policy = unquote(policy)
      termination = unquote(termination)
      parent_id = unique_id("permanent-parent")
      child_id = "#{parent_id}/worker"
      {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: parent_id, restart: :temporary)
      {:ok, unrelated} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("unrelated"))
      supervisor = Process.whereis(Jido.agent_supervisor_name(jido))
      supervisor_ref = Process.monitor(supervisor)
      unrelated_ref = Process.monitor(unrelated)

      assert {:ok, _agent} =
               Server.call(
                 parent,
                 signal("runtime.directive", %{
                   event: :spawned,
                   directive:
                     Directive.spawn_agent(ChildAgent, :worker,
                       restart: :permanent,
                       opts: %{on_parent_death: policy}
                     )
                 })
               )

      child = eventually(fn -> Server.children(parent)[:worker] end)
      child_ref = Process.monitor(child.pid)

      assert :ok = terminate_parent(jido, parent, termination)

      await_child_after_parent_death(policy, child.pid, child_ref)

      eventually(fn -> Jido.whereis_agent(jido, child_id) == nil end, timeout: 2_000)
      assert Process.alive?(supervisor)
      assert Process.alive?(unrelated)
      refute_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}
      refute_receive {:DOWN, ^unrelated_ref, :process, ^unrelated, _reason}
    end
  end

  defp terminate_parent(jido, parent, :normal), do: Jido.stop_agent(jido, parent)

  defp terminate_parent(_jido, parent, :kill) do
    Process.exit(parent, :kill)
    :ok
  end

  defp await_child_after_parent_death(:stop, _child, child_ref) do
    assert_receive {:DOWN, ^child_ref, :process, _pid, _reason}, 2_000
  end

  defp await_child_after_parent_death(policy, child, child_ref)
       when policy in [:continue, :emit_orphan] do
    eventually(fn -> Server.status(child).runtime.parent == nil end)
    Process.exit(child, :kill)
    assert_receive {:DOWN, ^child_ref, :process, _pid, :killed}, 2_000
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
