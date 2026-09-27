defmodule Jido.AgentServer.ChildOperationTaskTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentRuntimeFixtures.{ChildAgent, RuntimeAgent}

  defmodule HeldFactory do
    def new(opts) do
      send(opts[:state].observer, {:child_starting, self()})

      receive do
        :release_child -> ChildAgent.new(Keyword.delete(opts, :state))
      end
    end
  end

  defmodule HeldProcess do
    def start_link(observer) do
      send(observer, {:child_starting, self()})

      receive do
        :release_child -> :ignore
      end
    end
  end

  defmodule HeldStopPlugin do
    use Jido.Plugin

    @impl true
    defdelegate child_spec(init),
      to: Jido.AgentServer.ChildOperationTaskTest.HeldStopPlugin.Server
  end

  defmodule HeldStopPlugin.Server do
    @behaviour Jido.Plugin

    def child_spec(init),
      do:
        Supervisor.child_spec(
          {Jido.AgentServer.ChildOperationTaskTest.HeldStopRuntime, init.options[:observer_key]},
          []
        )
  end

  defmodule HeldStopRuntime do
    use GenServer
    def start_link(key), do: GenServer.start_link(__MODULE__, key)

    def init(key) do
      observer = :persistent_term.get({__MODULE__, key})
      Process.flag(:trap_exit, true)
      send(observer, {:stop_runtime, self()})
      {:ok, observer}
    end

    def terminate(_reason, observer) do
      send(observer, {:child_stopping, self()})

      receive do
        :release_stop -> :ok
      end
    end
  end

  test "child creation keeps inspections responsive and serializes later Turns", %{jido: jido} do
    for directive <- [
          Directive.spawn_child(HeldFactory, :worker,
            opts: %{initial_state: %{observer: self()}}
          ),
          Directive.spawn_process(%{id: HeldProcess, start: {HeldProcess, :start_link, [self()]}})
        ] do
      {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id(), directive_timeout: 20)

      assert {:ok, committed} =
               Server.call(
                 parent,
                 signal("runtime.directive", %{event: :created, directive: directive})
               )

      assert_receive {:child_starting, starter}, 2_000
      next = Task.async(fn -> Server.call(parent, signal("runtime.record", %{event: :next})) end)

      try do
        assert %{phase: :directing, state_version: 1} = Server.status(parent, 500)
        assert Server.snapshot(parent).agent == committed
        assert Server.cancel(parent) == {:error, :directing}
        assert :ok = Server.attach(parent)
        eventually(fn -> Server.status(parent).admission.postponed == 1 end)
      after
        send(starter, :release_child)
      end

      assert {:ok, agent} = Task.await(next)
      assert agent.state.events == [:created, :next]
      assert Server.status(parent).runtime.lifecycle.attached == 1
    end
  end

  test "a failed start worker preserves uncertainty and accepts the eventual child", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id(), debug: true)

    directive =
      Directive.spawn_child(HeldFactory, :worker, opts: %{initial_state: %{observer: self()}})

    assert {:ok, committed} =
             Server.call(
               parent,
               signal("runtime.directive", %{event: :created, directive: directive})
             )

    assert_receive {:child_starting, starter}, 2_000

    try do
      {:directing, data} = :sys.get_state(parent)
      worker = data.child_task.task.pid
      ref = Process.monitor(worker)
      Process.exit(worker, :kill)
      assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
      eventually(fn -> Server.status(parent).phase == :idle end)
      assert Server.snapshot(parent).agent == committed
      assert %{worker: %{node: target}} = Server.status(parent).runtime.pending_child_spawns
      assert target == node()

      assert {:error, {:child_spawn_pending, :worker, ^target, _request}} =
               Server.stop_child(parent, :worker)

      assert {:ok, events} = Server.recent_events(parent)

      assert Enum.any?(
               events,
               &match?(
                 %{event: :turn_failed, metadata: %{outcome: %{status: :indeterminate}}},
                 &1
               )
             )
    after
      send(starter, :release_child)
    end

    child = eventually(fn -> Server.children(parent)[:worker] end)
    assert Server.status(child.pid).runtime.parent.pid == parent
  end

  test "stop retires an active request while its crashed child is restarting", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id())
    child_id = unique_id()

    directive =
      Directive.spawn_child(HeldFactory, :worker,
        restart: :permanent,
        opts: %{id: child_id, initial_state: %{observer: self()}}
      )

    assert {:ok, _} =
             Server.call(
               parent,
               signal("runtime.directive", %{event: :created, directive: directive})
             )

    assert_receive {:child_starting, starter}, 2_000
    send(starter, :release_child)
    child = eventually(fn -> Server.children(parent)[:worker] end)
    ref = Process.monitor(child.pid)
    Process.exit(child.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _, :killed}
    assert_receive {:child_starting, restart}, 2_000

    stop =
      try do
        eventually(fn -> Server.children(parent)[:worker] == nil end)
        stop = Task.async(fn -> Server.stop_child(parent, :worker) end)

        eventually(fn ->
          match?(
            %{status: :closed},
            Jido.RuntimeStore.get(jido, :agent_spawn_requests, {parent, :worker})
          )
        end)

        assert %{phase: :directing} = Server.status(parent, 500)
        stop
      after
        send(restart, :release_child)
      end

    assert :ok = Task.await(stop)
    assert Jido.whereis_agent(jido, child_id) == nil
    assert Server.children(parent)[:worker] == nil
    assert :error = Jido.agent_parent_binding(jido, child_id)
  end

  test "adoption and stop keep the Server responsive and retain its monitor ownership", %{
    jido: jido
  } do
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id())
    key = unique_id()
    :persistent_term.put({HeldStopRuntime, key}, self())
    on_exit(fn -> :persistent_term.erase({HeldStopRuntime, key}) end)
    definition = %{ChildAgent.definition() | plugins: [{HeldStopPlugin, observer_key: key}]}
    {:ok, child} = Jido.start_agent(jido, definition, id: unique_id())
    assert_receive {:stop_runtime, runtime}
    on_exit(fn -> send(runtime, :release_stop) end)
    initial = Server.snapshot(parent)
    initial_children = Server.children(parent)

    :ok = :sys.suspend(child)
    adopt = Task.async(fn -> Server.adopt_child(parent, child, :worker) end)

    try do
      eventually(fn -> Server.status(parent, 500).phase == :directing end)
      assert Server.snapshot(parent) == initial
      assert :ok = Server.attach(parent)
    after
      :sys.resume(child)
    end

    assert :ok = Task.await(adopt)
    assert {:monitors, monitors} = Process.info(parent, :monitors)
    assert {:process, child} in monitors

    stop = Task.async(fn -> Server.stop_child(parent, :worker) end)
    assert_receive {:child_stopping, ^runtime}, 2_000

    try do
      eventually(fn -> Server.status(parent, 500).phase == :directing end)
      assert Server.snapshot(parent) == initial
      assert :ok = Server.detach(parent)
    after
      send(runtime, :release_stop)
    end

    assert :ok = Task.await(stop)
    assert Server.children(parent) == initial_children
    assert Server.status(parent).runtime.lifecycle.attached == 0
    assert Server.snapshot(parent) == initial
  end

  test "a late local start cannot leave a child after its owner stops", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, RuntimeAgent, id: unique_id(), restart: :temporary)
    child_id = unique_id()

    directive =
      Directive.spawn_child(HeldFactory, :worker,
        opts: %{id: child_id, initial_state: %{observer: self()}}
      )

    assert {:ok, _} =
             Server.call(
               parent,
               signal("runtime.directive", %{event: :created, directive: directive})
             )

    assert_receive {:child_starting, starter}, 2_000

    try do
      assert :ok = Server.stop(parent)
    after
      send(starter, :release_child)
    end

    # A supervisor call follows the held start and its request cleanup.
    DynamicSupervisor.which_children(Jido.agent_supervisor_name(jido))
    assert Jido.whereis_agent(jido, child_id) == nil
  end
end
