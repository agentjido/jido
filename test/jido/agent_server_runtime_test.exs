defmodule Jido.AgentServerRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ParentRef
  alias Jido.Agent.Turn.Outcome
  alias Jido.Plugin.Scheduler
  alias Jido.Signal
  alias Jido.Signal.ID

  defmodule OwnedExecutionAction do
    use Jido.Action, name: "agent_owned_execution"

    @impl true
    def run(%{test: test, gate: gate, label: label}, context) do
      send(test, {:owned_execution, label, self()})

      receive do
        {:release, ^gate} -> {:ok, context.agent_state}
      end
    end
  end

  defmodule OwnedExecutionFlow do
    use Jido.Flow, name: "agent_owned_execution_flow"

    flow do
      step "owned",
        action: OwnedExecutionAction,
        params: %{test: input(:test), gate: input(:gate), label: input(:label)}

      output result("owned")
    end
  end

  defmodule OwnedExecutionAgent do
    use Jido.Agent,
      name: "agent_owned_execution_agent",
      routes: [
        {"owned.action", OwnedExecutionAction},
        {"owned.flow", OwnedExecutionFlow}
      ]
  end

  defmodule ObservedExec do
    def run_async(executable, input, context, opts) do
      test = Map.get(input, :test) || get_in(input, [:signal, Access.key(:data), :test])
      Process.put(__MODULE__, test)
      Jido.Exec.run_async(executable, input, context, opts)
    end

    def handle_message(handle, message) do
      send(Process.get(__MODULE__), {:exec_message, message})
      Jido.Exec.handle_message(handle, message)
    end

    defdelegate cancel(handle), to: Jido.Exec
  end

  defmodule CountedDirective do
    defstruct [:test]
  end

  defmodule ReturnCountedDirective do
    use Jido.Action, name: "agent_return_counted_directive"

    @impl Jido.Action
    def run(%{test: test}, context) do
      {:ok, context.agent_state, [%CountedDirective{test: test}]}
    end
  end

  defmodule CountedDirectivePlugin do
    use Jido.Plugin

    @impl true
    def prepare(command, _opts) do
      {:ok, %{command | signal: %{command.signal | source: "/plugin-prepared"}}}
    end

    @impl true
    def directives(_opts), do: [CountedDirective]

    @impl true
    def validate_directive(%CountedDirective{test: test} = directive, _opts) do
      send(test, :directive_validated)
      {:ok, directive}
    end

    @impl true
    def dispatch(_runtime, %CountedDirective{test: test}, context, _opts) do
      send(test, {:directive_dispatched, context})
      :ok
    end

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end
  end

  defmodule CountedDirectiveAgent do
    use Jido.Agent,
      name: "counted_directive_agent",
      routes: [{"directive.count", ReturnCountedDirective}],
      plugins: [CountedDirectivePlugin]
  end

  defmodule SlowDirective do
    defstruct [:test, :gate, :server]
  end

  defmodule ReturnSlowDirective do
    use Jido.Action, name: "agent_return_slow_directive"

    @impl Jido.Action
    def run(%{test: test} = params, context) do
      directive = %SlowDirective{
        test: test,
        gate: Map.get(params, :gate),
        server: Map.get(params, :server)
      }

      {:ok, context.agent_state, [directive]}
    end
  end

  defmodule SlowDirectivePlugin do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [SlowDirective]

    @impl true
    def validate_directive(%SlowDirective{} = directive, _opts), do: {:ok, directive}

    @impl true
    def dispatch(_runtime, %SlowDirective{test: test, gate: gate}, _context, _opts)
        when not is_nil(gate) do
      send(test, {:plugin_directive_blocked, gate, self()})

      receive do
        {:release, ^gate} -> :ok
      end
    end

    def dispatch(_runtime, %SlowDirective{test: test, server: server}, _context, _opts)
        when is_pid(server) do
      signal = Signal.new!("directive.slow", %{test: test}, source: "/plugin/directive")
      send(test, {:plugin_directive_reentry, Server.call(server, signal)})
      :ok
    end

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end
  end

  defmodule SlowDirectiveAgent do
    use Jido.Agent,
      name: "slow_directive_agent",
      routes: [{"directive.slow", ReturnSlowDirective}],
      plugins: [SlowDirectivePlugin]
  end

  defmodule ReadinessRuntime do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init), do: {:ok, init, {:continue, :initialize}}

    @impl true
    def handle_continue(:initialize, init) do
      test = Process.whereis(:jido_agent_plugin_readiness_test)
      send(test, {:plugin_initializing, self()})

      receive do
        :release -> {:noreply, init}
      end
    end

    @impl true
    def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}
  end

  defmodule ReadinessPlugin do
    use Jido.Plugin

    @impl true
    def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

    def child_spec(init) do
      Supervisor.child_spec({ReadinessRuntime, init}, id: __MODULE__)
    end
  end

  defmodule ReadinessAgent do
    use Jido.Agent,
      name: "readiness_agent",
      plugins: [ReadinessPlugin]
  end

  defmodule GenerationRuntime do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init) do
      notify({:generation_started, self()})
      {:ok, init}
    end

    @impl true
    def terminate(_reason, _state) do
      case Process.whereis(:jido_agent_generation_test) do
        nil ->
          :ok

        test ->
          send(test, {:generation_stopping, self()})

          receive do
            :release_generation_stop -> :ok
          end
      end
    end

    defp notify(message) do
      if test = Process.whereis(:jido_agent_generation_test), do: send(test, message)
      :ok
    end
  end

  defmodule GenerationPlugin do
    use Jido.Plugin

    def child_spec(init) do
      Supervisor.child_spec({GenerationRuntime, init}, id: __MODULE__)
    end
  end

  defmodule GenerationAgent do
    use Jido.Agent,
      name: "generation_agent",
      plugins: [GenerationPlugin]
  end

  defmodule FreshRuntimeDirective do
    defstruct [:value]
  end

  defmodule ReturnFreshRuntimeDirective do
    use Jido.Action, name: "agent_return_fresh_runtime_directive"

    @impl Jido.Action
    def run(%{value: value}, context) do
      {:ok, context.agent_state, [%FreshRuntimeDirective{value: value}]}
    end
  end

  defmodule FreshRuntimePlugin do
    use GenServer
    use Jido.Plugin

    @impl Jido.Plugin
    def state_spec(_opts) do
      {:fresh_runtime,
       Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}) |> Zoi.default(%{value: 0})}
    end

    @impl Jido.Plugin
    def update_state(state, [%FreshRuntimeDirective{value: value}], _opts) do
      {:ok, %{state | value: value}}
    end

    @impl Jido.Plugin
    def directives(_opts), do: [FreshRuntimeDirective]

    @impl Jido.Plugin
    def validate_directive(%FreshRuntimeDirective{} = directive, _opts),
      do: {:ok, directive}

    @impl Jido.Plugin
    def dispatch(_runtime, _directive, _context, _opts), do: :ok

    @impl Jido.Plugin
    def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl GenServer
    def init(init), do: {:ok, %{init: init, plugin_state: nil}, {:continue, :load_state}}

    @impl GenServer
    def handle_continue(:load_state, state) do
      {:ok, plugin_state} = Jido.Plugin.state(state.init)
      notify({:fresh_runtime_started, self(), plugin_state})
      {:noreply, %{state | plugin_state: plugin_state}}
    end

    @impl GenServer
    def handle_call(:await_ready, _from, state) do
      notify({:fresh_runtime_ready, self(), state.plugin_state})
      {:reply, :ok, state}
    end

    defp notify(message) do
      if test = Process.whereis(:jido_agent_fresh_runtime_test), do: send(test, message)
      :ok
    end
  end

  defmodule FreshRuntimeAgent do
    use Jido.Agent,
      name: "fresh_runtime_agent",
      routes: [{"runtime.fresh", ReturnFreshRuntimeDirective}],
      plugins: [FreshRuntimePlugin]
  end

  alias JidoTest.AgentRuntimeFixtures.{
    BootPlugin,
    ChildAgent,
    PluginRuntimeAgent,
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

  test "Jido instance APIs start, find, list, and stop Agents", %{jido: jido} do
    id = unique_id("agent")
    assert {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)
    assert Jido.whereis_agent(jido, id) == pid
    assert {id, pid} in Jido.list_agents(jido)
    assert Jido.agent_count(jido) == 1
    assert :ok = Jido.stop_agent(jido, id)
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "owns Action and Flow execution under the Agent Jido instance", %{jido: jido} do
    {:ok, agent} =
      Jido.start_agent(jido, OwnedExecutionAgent, id: unique_id("owned-execution"))

    task_supervisor = Process.whereis(Jido.task_supervisor_name(jido))
    assert is_pid(task_supervisor)
    test = self()

    for {type, label} <- [{"owned.action", :action}, {"owned.flow", :flow}] do
      gate = make_ref()

      caller =
        Task.async(fn ->
          Server.call(agent, signal(type, %{test: test, gate: gate, label: label}))
        end)

      assert_receive {:owned_execution, ^label, action_worker}, 2_000
      assert action_worker in Task.Supervisor.children(task_supervisor)

      {:running, state} = :sys.get_state(agent)
      exec_root = state.active.exec_handle.pid
      assert exec_root in Task.Supervisor.children(task_supervisor)
      assert agent in elem(Process.info(exec_root, :links), 1)

      send(action_worker, {:release, gate})
      assert {:ok, _agent} = Task.await(caller, 2_000)
    end
  end

  test "Exec receives general messages and unowned DOWN events after attachment handling", %{
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent, exec_module: ObservedExec)
    owner = start_supervised!({Elixir.Agent, fn -> nil end})
    assert :ok = Server.attach(server, owner)
    gate = make_ref()
    test = self()

    caller =
      Task.async(fn ->
        Server.call(server, signal("owned.action", %{test: test, gate: gate, label: :routing}))
      end)

    assert_receive {:owned_execution, :routing, worker}, 2_000
    {:running, state} = :sys.get_state(server)
    owner_ref = Map.fetch!(state.attachments, owner)
    Elixir.Agent.stop(owner)
    eventually(fn -> Server.status(server).runtime.lifecycle.attached == 0 end)
    refute_received {:exec_message, {:DOWN, ^owner_ref, :process, ^owner, _}}

    unknown = make_ref()
    down = {:DOWN, unknown, :process, owner, :normal}
    send(server, down)
    send(server, {:exec_probe, gate})
    assert Server.status(server).phase == :running
    assert_receive {:exec_message, ^down}
    assert_receive {:exec_message, {:exec_probe, ^gate}}
    send(worker, {:release, gate})
    assert {:ok, _} = Task.await(caller)
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Server.status(server).state_version == 1
  end

  test "Agent death stops its linked Exec and Action work", %{jido: jido} do
    id = unique_id("owned-exec-stop")
    {:ok, agent} = Jido.start_agent(jido, OwnedExecutionAgent, id: id)
    gate = make_ref()

    Server.cast(agent, signal("owned.action", %{test: self(), gate: gate, label: :kill}))
    assert_receive {:owned_execution, :kill, action_worker}, 2_000

    {:running, state} = :sys.get_state(agent)
    exec_root = state.active.exec_handle.pid
    action_ref = Process.monitor(action_worker)
    exec_ref = Process.monitor(exec_root)

    Process.exit(agent, :kill)

    assert_receive {:DOWN, ^exec_ref, :process, ^exec_root, _reason}, 2_000
    assert_receive {:DOWN, ^action_ref, :process, ^action_worker, _reason}, 2_000
  end

  test "starts and owns a Plugin runtime child outside Agent state", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, PluginRuntimeAgent, id: unique_id("plugin-runtime"))

    agent =
      eventually_agent(pid, fn agent ->
        agent.state.events == [:plugin_booted] and agent.state.boot.calls == 1
      end)

    refute Map.has_key?(agent.state, :children)
    refute Enum.any?(Map.values(agent.state), &is_pid/1)

    child = eventually(fn -> Server.children(pid)[{:plugin, BootPlugin}] end)
    assert child.kind == :plugin
    assert child.module == BootPlugin
    assert Process.alive?(child.pid)

    monitor = Process.monitor(child.pid)
    assert :ok = Jido.stop_agent(jido, pid)
    assert_receive {:DOWN, ^monitor, :process, _pid, :shutdown}, 2_000
  end

  test "does not report the Agent ready before its Plugin runtime is ready", %{jido: jido} do
    Process.register(self(), :jido_agent_plugin_readiness_test)

    on_exit(fn ->
      if Process.whereis(:jido_agent_plugin_readiness_test) == self() do
        Process.unregister(:jido_agent_plugin_readiness_test)
      end
    end)

    task =
      Task.async(fn ->
        Jido.start_agent(jido, ReadinessAgent, id: unique_id("plugin-readiness"))
      end)

    assert_receive {:plugin_initializing, runtime}
    refute Task.yield(task, 50)

    send(runtime, :release)
    assert {:ok, pid} = Task.await(task, 2_000)
    assert Process.alive?(pid)
  end

  test "does not overlap Plugin runtime generations after an Agent crash", %{jido: jido} do
    Process.register(self(), :jido_agent_generation_test)

    on_exit(fn ->
      if Process.whereis(:jido_agent_generation_test) == self() do
        Process.unregister(:jido_agent_generation_test)
      end
    end)

    id = unique_id("plugin-generation")
    {:ok, agent} = Jido.start_agent(jido, GenerationAgent, id: id)
    assert_receive {:generation_started, first_runtime}, 2_000

    Process.exit(agent, :kill)
    assert_receive {:generation_stopping, ^first_runtime}, 2_000
    refute_receive {:generation_started, _new_runtime}, 100

    send(first_runtime, :release_generation_stop)
    assert_receive {:generation_started, second_runtime}, 2_000
    refute second_runtime == first_runtime

    restarted = eventually(fn -> Jido.whereis_agent(jido, id) end)
    assert Process.alive?(restarted)
  end

  test "refreshes Plugin state and readiness after an internal runtime restart", %{jido: jido} do
    Process.register(self(), :jido_agent_fresh_runtime_test)

    on_exit(fn ->
      if Process.whereis(:jido_agent_fresh_runtime_test) == self() do
        Process.unregister(:jido_agent_fresh_runtime_test)
      end
    end)

    {:ok, pid} = Jido.start_agent(jido, FreshRuntimeAgent, id: unique_id("fresh-runtime"))

    assert_receive {:fresh_runtime_started, first_runtime, %{value: 0}}, 2_000
    assert_receive {:fresh_runtime_ready, ^first_runtime, %{value: 0}}, 2_000

    assert {:ok, agent} =
             Server.call(pid, signal("runtime.fresh", %{value: 7}))

    assert agent.state.fresh_runtime.value == 7
    eventually(fn -> Server.status(pid).phase == :idle end)

    child = Server.children(pid)[{:plugin, FreshRuntimePlugin}]
    assert child.pid == first_runtime
    monitor = Process.monitor(first_runtime)
    Process.exit(first_runtime, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first_runtime, :killed}, 2_000

    assert_receive {:fresh_runtime_started, restarted_runtime, %{value: 7}}, 2_000
    refute restarted_runtime == first_runtime
    assert_receive {:fresh_runtime_ready, ^restarted_runtime, %{value: 7}}, 2_000

    eventually(fn ->
      Server.children(pid)[{:plugin, FreshRuntimePlugin}].pid == restarted_runtime
    end)
  end

  test "restores the last committed Agent when a required Plugin runtime is lost", %{jido: jido} do
    id = unique_id("required-plugin")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)

    assert {:ok, committed_agent} =
             Server.call(pid, signal("runtime.record", %{event: :committed_before_restart}))

    assert committed_agent.state.events == [:committed_before_restart]
    assert Server.status(pid).state_version == 1

    {_phase, state} = :sys.get_state(pid)
    plugin = state.children[{:plugin, Scheduler}]
    monitor = Process.monitor(pid)

    Process.exit(plugin.lifecycle_pid, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 2_000

    restarted_pid =
      eventually(
        fn ->
          case Jido.whereis_agent(jido, id) do
            new_pid when is_pid(new_pid) and new_pid != pid -> new_pid
            _other -> nil
          end
        end,
        timeout: 3_000
      )

    restarted_agent = Server.agent(restarted_pid)
    assert restarted_agent.state.events == [:committed_before_restart]
    assert restarted_agent.state.ticks == 0
    assert restarted_agent.state.scheduler == %{cron: %{}}
    assert Server.status(restarted_pid).state_version == 1
  end

  test "commits Agent state before it emits a follow-up Signal", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("emit"))
    follow_up = Signal.new!("runtime.record", %{event: :follow_up}, source: "/test")
    directive = Directive.emit(follow_up)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{event: :committed, directive: directive})
             )

    assert agent.state.events == [:committed]

    agent = eventually_agent(pid, &(&1.state.events == [:committed, :follow_up]))
    assert agent.state.events == [:committed, :follow_up]
    assert %{state_version: 2} = Server.status(pid)
  end

  test "rejects an invalid built-in Directive before the Agent commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("invalid-directive"))
    invalid = %Directive.Emit{signal: :not_a_signal}

    assert {:error, %Jido.Error.ValidationError{}} =
             Server.call(
               pid,
               signal("runtime.directive", %{event: :must_not_commit, directive: invalid})
             )

    assert Server.agent(pid).state.events == []
    assert Server.status(pid).state_version == 0
  end

  test "validates a Plugin Directive once in a live turn", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, CountedDirectiveAgent, id: unique_id("directive-validation"))

    assert {:ok, _agent} =
             Server.call(pid, signal("directive.count", %{test: self()}))

    assert_receive :directive_validated
    refute_receive :directive_validated, 50

    assert_receive {:directive_dispatched, context}
    assert ID.valid?(context.turn_id)
    assert context.source_signal.source == "/test"
    assert context.effective_signal.source == "/plugin-prepared"
    refute Map.has_key?(context, :agent)
  end

  test "keeps the Server responsive during Plugin Directive dispatch", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, SlowDirectiveAgent, id: unique_id("slow-directive"))
    gate = make_ref()

    assert {:ok, _agent} =
             Server.call(pid, signal("directive.slow", %{test: self(), gate: gate}))

    assert_receive {:plugin_directive_blocked, ^gate, worker}
    assert %{phase: :directing, state_version: 1} = Server.status(pid, 500)
    assert {:directing, _state} = :sys.get_state(pid, 500)

    send(worker, {:release, gate})
    eventually(fn -> Server.status(pid).phase == :idle end)
  end

  test "Directive task exit retains the commit and ignores stale timeouts", %{jido: jido} do
    test = self()

    policy = fn error, outcome ->
      send(test, {:dispatch_failed, error, outcome})
      :continue
    end

    {:ok, pid} =
      Jido.start_agent(jido, SlowDirectiveAgent, directive_timeout: 10_000, error_policy: policy)

    gate = make_ref()

    assert {:ok, committed} =
             Server.call(pid, signal("directive.slow", %{test: test, gate: gate}))

    assert_receive {:plugin_directive_blocked, ^gate, worker}
    monitor = Process.monitor(worker)
    {:directing, state} = :sys.get_state(pid)
    %{task: task, timer: timer} = state.directive_task
    send(pid, {:timeout, make_ref(), {:directive_timeout, task.ref}})
    send(pid, {:timeout, timer, {:directive_timeout, make_ref()}})
    assert Server.status(pid).phase == :directing
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}

    assert_receive {:dispatch_failed, %Jido.Error.ExecutionError{},
                    %Outcome{
                      status: :failed,
                      stage: :directive,
                      committed?: true,
                      directives: %{failed: 1, failed_index: 0}
                    }}

    eventually(fn -> Server.status(pid).phase == :idle end)
    assert Server.snapshot(pid) == %{agent: committed, state_version: 1}
    assert Process.read_timer(timer) == false

    next_gate = make_ref()
    assert {:ok, _} = Server.call(pid, signal("directive.slow", %{test: test, gate: next_gate}))
    assert_receive {:plugin_directive_blocked, ^next_gate, next_worker}
    {:directing, next_state} = :sys.get_state(pid)
    send(pid, {task.ref, {:error, :stale}})
    send(pid, {:timeout, timer, {:directive_timeout, task.ref}})
    assert Server.status(pid).phase == :directing
    send(next_worker, {:release, next_gate})
    eventually(fn -> Server.status(pid).phase == :idle end)
    assert Process.read_timer(next_state.directive_task.timer) == false
    {:monitors, monitors} = Process.info(pid, :monitors)
    refute {:process, next_worker} in monitors
    assert Server.status(pid).state_version == 2
  end

  test "times out owned Plugin Directive work and records exact progress", %{jido: jido} do
    test = self()

    policy = fn reason, outcome ->
      send(test, {:directive_timeout, reason, outcome})
      :continue
    end

    {:ok, pid} =
      Jido.start_agent(jido, SlowDirectiveAgent,
        id: unique_id("directive-timeout"),
        directive_timeout: 25,
        error_policy: policy
      )

    gate = make_ref()
    assert {:ok, _agent} = Server.call(pid, signal("directive.slow", %{test: self(), gate: gate}))
    assert_receive {:plugin_directive_blocked, ^gate, worker}
    worker_ref = Process.monitor(worker)

    assert_receive {:directive_timeout, %Jido.Error.TimeoutError{},
                    %Outcome{
                      status: :timed_out,
                      stage: :directive,
                      directives: %{
                        total: 1,
                        completed: 0,
                        failed: 1,
                        failed_index: 0,
                        skipped: 0
                      }
                    }},
                   2_000

    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
    eventually(fn -> Server.status(pid).phase == :idle end)
  end

  test "a supervised Agent stop terminates owned Directive work", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, SlowDirectiveAgent, id: unique_id("directive-stop"))
    gate = make_ref()

    assert {:ok, _agent} = Server.call(pid, signal("directive.slow", %{test: self(), gate: gate}))
    assert_receive {:plugin_directive_blocked, ^gate, worker}
    worker_ref = Process.monitor(worker)

    assert :ok = Jido.stop_agent(jido, pid)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
  end

  test "rejects a synchronous call from Plugin Directive dispatch", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, SlowDirectiveAgent, id: unique_id("directive-reentry"))

    assert {:ok, _agent} =
             Server.call(pid, signal("directive.slow", %{test: self(), server: pid}))

    assert_receive {:plugin_directive_reentry, {:error, :reentrant_directive}}
    eventually(fn -> Server.status(pid).phase == :idle end)
  end

  test "exposes only one declared Plugin state slice", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("plugin-state"))

    assert {:ok, %{cron: %{}}} = Server.plugin_state(pid, Scheduler)
    assert {:error, {:plugin_not_declared, String}} = Server.plugin_state(pid, String)
  end

  test "keeps the commit but stops a Directive batch after a runtime failure", %{jido: jido} do
    test_pid = self()

    error_policy = fn reason, %Outcome{} = outcome ->
      send(test_pid, {:directive_failure, reason, outcome})
      :continue
    end

    {:ok, pid} =
      Jido.start_agent(jido, RuntimeAgent,
        id: unique_id("directive-failure"),
        error_policy: error_policy
      )

    follow_up = Signal.new!("runtime.record", %{event: :must_not_run}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :committed,
                 directives: [
                   Directive.emit_to_parent(follow_up),
                   Directive.emit(follow_up)
                 ]
               })
             )

    assert agent.state.events == [:committed]

    assert_receive {:directive_failure, reason,
                    %Outcome{
                      status: :failed,
                      stage: :directive,
                      committed?: true,
                      state_version_before: 0,
                      state_version_after: 1,
                      directives: %{total: 2, failed: 1}
                    } = outcome}

    assert outcome.error == reason
    assert ID.valid?(outcome.id)

    assert {:ok, barrier} =
             Server.call(pid, signal("runtime.record", %{event: :barrier}))

    assert barrier.state.events == [:committed, :barrier]
  end

  test "waits for external Emit results and skips later Directives after failure", %{jido: jido} do
    test = self()
    {dead_target, dead_ref} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^dead_ref, :process, ^dead_target, :normal}

    policy = fn reason, outcome ->
      send(test, {:emit_failed, reason, outcome})
      :continue
    end

    {:ok, pid} =
      Jido.start_agent(jido, RuntimeAgent,
        id: unique_id("emit-result"),
        error_policy: policy
      )

    output = Signal.new!("runtime.record", %{event: :must_not_run}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :committed,
                 directives: [
                   Directive.emit_to_pid(output, dead_target),
                   Directive.emit_to_pid(output, self())
                 ]
               })
             )

    assert agent.state.events == [:committed]

    assert_receive {:emit_failed, {:emit_dispatch_failed, _reason},
                    %Outcome{
                      directives: %{
                        total: 2,
                        completed: 0,
                        failed: 1,
                        failed_index: 0,
                        skipped: 1
                      }
                    }},
                   2_000

    refute_receive {:signal, %Signal{type: "runtime.record"}}, 100
  end

  test "counts consecutive post-commit Directive failures", %{jido: jido} do
    id = unique_id("max-directive-errors")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id, error_policy: {:max_errors, 2})
    monitor = Process.monitor(pid)
    output = Signal.new!("runtime.record", %{}, source: "/test")

    for event <- [:first, :second] do
      assert {:ok, _agent} =
               Server.call(
                 pid,
                 signal("runtime.directive", %{
                   event: event,
                   directive: Directive.emit_to_parent(output)
                 })
               )

      if event == :first do
        eventually(fn -> Server.status(pid).runtime.error_count == 1 end)
      end
    end

    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, {:max_agent_errors, _reason}}},
                   2_000

    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "rejects a self-directed emit error policy", %{jido: jido} do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.start_agent(jido, RuntimeAgent,
               id: unique_id("invalid-error-policy"),
               error_policy: {:emit_signal, nil}
             )

    assert message =~ "requires an external dispatch target"
  end

  test "does not restart stale state after a post-commit Directive failure", %{jido: jido} do
    id = unique_id("post-commit-failure")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id, error_policy: :stop_on_error)
    monitor = Process.monitor(pid)
    follow_up = Signal.new!("runtime.record", %{event: :must_not_run}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :committed,
                 directive: Directive.emit_to_parent(follow_up)
               })
             )

    assert agent.state.events == [:committed]

    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, {:agent_error, _reason}}},
                   2_000

    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "delayed and cron Signals return through the Agent mailbox", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("schedule"))

    delayed = Signal.new!("runtime.record", %{event: :delayed}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :scheduled,
                 directive: Scheduler.schedule(10, delayed)
               })
             )

    assert agent.state.events == [:scheduled]
    eventually_agent(pid, &(&1.state.events == [:scheduled, :delayed]))

    tick = Signal.new!("cron.tick", %{}, source: "/test")

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :cron_registered,
                 directive: Scheduler.cron(:heartbeat, "* * * * * * *", tick)
               })
             )

    assert Map.has_key?(Server.agent(pid).state.scheduler.cron, :heartbeat)
    eventually_agent(pid, &(&1.state.ticks > 0), 5_000)

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :cron_cancelled,
                 directive: Scheduler.cancel(:heartbeat)
               })
             )

    eventually(fn -> Server.agent(pid).state.scheduler.cron == %{} end)
  end

  test "rejects invalid Scheduler data before commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("invalid-scheduler"))
    tick = Signal.new!("cron.tick", %{}, source: "/test")

    for directive <- [
          Scheduler.schedule(10, :not_a_signal),
          Scheduler.cron(:raw_message, "* * * * * * *", :not_a_signal),
          Scheduler.cron(:bad_cron, "not a cron", tick),
          Scheduler.cron(make_ref(), "* * * * * * *", tick),
          Scheduler.cron(:bad_timezone, "* * * * * * *", tick, timezone: "Not/AZone"),
          Scheduler.cron(:bad_generation, "* * * * * * *", tick, generation: -1),
          Scheduler.cron(:bad_generation_type, "* * * * * * *", tick, generation: "1"),
          Scheduler.cron(:large_generation, "* * * * * * *", tick, generation: 2_147_483_648)
        ] do
      assert {:error, _reason} =
               Server.call(
                 pid,
                 signal("runtime.directive", %{event: :must_not_commit, directive: directive})
               )
    end

    assert Server.agent(pid).state.events == []
    assert Server.agent(pid).state.scheduler.cron == %{}
    assert Server.status(pid).state_version == 0

    agent = Server.agent(pid)

    invalid_state =
      put_in(agent.state.scheduler.cron[:restored], %{
        cron_expression: "not a cron",
        message: tick,
        timezone: "Etc/UTC"
      })

    assert {:error, %Jido.Error.ValidationError{}} = Jido.Agent.transition(agent, invalid_state)
  end

  test "reduces Scheduler changes in list order and reconciles the final state", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("scheduler-order"))
    tick = Signal.new!("cron.tick", %{}, source: "/test")
    cron = Scheduler.cron(:heartbeat, "* * * * * * *", tick)
    cancel = Scheduler.cancel(:heartbeat)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :enabled,
                 directives: [cancel, cron]
               })
             )

    assert Map.has_key?(agent.state.scheduler.cron, :heartbeat)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :disabled,
                 directives: [cron, cancel]
               })
             )

    assert agent.state.scheduler.cron == %{}
  end

  test "restarts the Scheduler runtime from committed Plugin state", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("scheduler-restart"))

    tick = Signal.new!("cron.tick", %{}, source: "/test")

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :scheduled,
                 directive: Scheduler.cron(:heartbeat, "* * * * * * *", tick)
               })
             )

    assert Map.has_key?(agent.state.scheduler.cron, :heartbeat)
    child = Server.children(pid)[{:plugin, Scheduler}]
    monitor = Process.monitor(child.pid)
    Process.exit(child.pid, :kill)

    assert_receive {:DOWN, ^monitor, :process, _pid, :killed}

    restarted =
      eventually(fn ->
        case Server.children(pid)[{:plugin, Scheduler}] do
          %{pid: new_pid} = current when new_pid != child.pid -> current
          _child -> nil
        end
      end)

    assert Process.alive?(restarted.pid)
    assert Map.has_key?(Server.agent(pid).state.scheduler.cron, :heartbeat)
    eventually_agent(pid, &(&1.state.ticks > 0), 5_000)
  end

  test "the Scheduler runtime restarts a failed cron Job", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("cron-job-restart"))
    tick = Signal.new!("cron.tick", %{}, source: "/test")

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :scheduled,
                 directive: Scheduler.cron(:heartbeat, "* * * * * * *", tick)
               })
             )

    scheduler = eventually(fn -> Server.children(pid)[{:plugin, Scheduler}] end)

    {_spec, old_job_pid, _ref} =
      eventually(fn ->
        :sys.get_state(scheduler.pid).cron_jobs[:heartbeat]
      end)

    monitor = Process.monitor(old_job_pid)
    Process.exit(old_job_pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^old_job_pid, :killed}, 2_000

    new_job_pid =
      eventually(fn ->
        case :sys.get_state(scheduler.pid).cron_jobs[:heartbeat] do
          {_spec, current_job, _ref}
          when is_pid(current_job) and current_job != old_job_pid ->
            current_job

          _job ->
            nil
        end
      end)

    assert Process.alive?(new_job_pid)

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :cancelled,
                 directive: Scheduler.cancel(:heartbeat)
               })
             )

    eventually(fn -> :sys.get_state(scheduler.pid).cron_jobs == %{} end)
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

  test "records bounded debug events without exposing Server state", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, RuntimeAgent,
        id: unique_id("debug"),
        debug: true,
        debug_max_events: 2
      )

    assert {:ok, _agent} = Server.call(pid, signal("runtime.record", %{event: :one}))
    assert {:ok, _agent} = Server.call(pid, signal("runtime.record", %{event: :two}))

    assert {:ok, events} = Server.recent_events(pid)
    assert length(events) == 2
    assert Enum.map(events, & &1.event) == [:turn_completed, :turn_committed]

    assert %Outcome{
             status: :succeeded,
             stage: :commit,
             committed?: true,
             state_version_before: 1,
             state_version_after: 2
           } = hd(events).metadata.outcome

    refute Enum.any?(events, &Map.has_key?(&1, :server_state))

    assert :ok = Server.set_debug(pid, false)
    assert {:error, :debug_not_enabled} = Server.recent_events(pid)
  end

  test "a Stop Directive commits once and does not restart a supervised Agent", %{jido: jido} do
    id = unique_id("stop")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)
    monitor = Process.monitor(pid)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :stopped,
                 directive: Directive.stop(:normal)
               })
             )

    assert agent.state.events == [:stopped]
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 2_000
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "normalizes an arbitrary Stop reason so stale state cannot restart", %{jido: jido} do
    id = unique_id("abnormal-stop")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)
    monitor = Process.monitor(pid)

    assert {:ok, agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :stopped,
                 directive: Directive.stop(:arbitrary_reason)
               })
             )

    assert agent.state.events == [:stopped]
    assert_receive {:DOWN, ^monitor, :process, ^pid, {:shutdown, :arbitrary_reason}}, 2_000
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "rejects a Stop Directive before later effects", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("stop-order"))
    output = Signal.new!("runtime.record", %{event: :must_not_run}, source: "/test")

    assert {:error, {:terminal_directive_not_last, %{index: 0}}} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :must_not_commit,
                 directives: [Directive.stop(), Directive.emit(output)]
               })
             )

    assert Server.agent(pid).state.events == []
    assert Server.status(pid).state_version == 0
  end

  test "emits Agent Signal and Directive telemetry with bounded metadata", %{jido: jido} do
    handler = "agent-runtime-#{System.unique_integer([:positive])}"
    owner = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:jido, :agent_server, :signal, :stop],
          [:jido, :agent_server, :directive, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(owner, {:agent_telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("telemetry"))
    follow_up = Signal.new!("runtime.record", %{event: :emitted}, source: "/test")

    assert {:ok, _agent} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :committed,
                 directive: Directive.emit(follow_up)
               })
             )

    assert_receive {:agent_telemetry, [:jido, :agent_server, :signal, :stop], measurements,
                    signal_meta},
                   2_000

    assert is_integer(measurements.duration)
    assert signal_meta.agent_id == Server.agent(pid).id
    assert signal_meta.signal_type == "runtime.directive"
    assert measurements.directive_count == 1
    refute Map.has_key?(signal_meta, :agent)
    refute Map.has_key?(signal_meta, :state)

    assert_receive {:agent_telemetry, [:jido, :agent_server, :directive, :stop], _measurements,
                    directive_meta},
                   2_000

    assert directive_meta.directive_type == "Emit"
  end
end
