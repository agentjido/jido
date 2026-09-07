defmodule Jido.AgentServer.DirectiveExecutionTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Turn.Outcome
  alias Jido.Plugin.Scheduler
  alias Jido.Signal
  alias Jido.Signal.ID
  alias JidoTest.AgentRuntimeFixtures.RuntimeAgent

  alias JidoTest.AgentServerRuntimeFixtures.{
    CountedDirectiveAgent,
    SlowDirectiveAgent
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

  test "rejects a malformed outbound Signal envelope before the Agent commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("invalid-signal"))
    malformed = %{Signal.new!("runtime.follow_up", %{}, source: "/test") | source: ""}
    invalid = Directive.emit(malformed)

    assert {:error, _reason} =
             Server.call(
               pid,
               signal("runtime.directive", %{event: :must_not_commit, directive: invalid})
             )

    assert Server.agent(pid).state.events == []
    assert Server.status(pid).state_version == 0
  end

  test "rejects an invalid Emit dispatch before the Agent commit", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: unique_id("invalid-emit"))
    before = Server.snapshot(pid)
    output = Signal.new!("runtime.record", %{event: :must_not_run}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Server.call(
               pid,
               signal("runtime.directive", %{
                 event: :must_not_commit,
                 directive: Directive.emit(output, :invalid)
               })
             )

    assert message =~ "Emit dispatch is invalid"
    assert Server.snapshot(pid) == before
    assert Server.status(pid).phase == :idle
  end

  test "rejects an invalid default Emit dispatch before startup", %{jido: jido} do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.start_agent(jido, RuntimeAgent,
               id: unique_id("invalid-default-emit"),
               default_dispatch: :invalid
             )

    assert message =~ "default_dispatch is invalid"
  end

  test "validates a Plugin Directive once in a live turn", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, CountedDirectiveAgent, id: unique_id("directive-validation"))

    assert {:ok, _agent} =
             Server.call(pid, signal("directive.count", %{test: self()}))

    assert_receive :directive_validated
    assert_receive {:directive_dispatched, context}
    refute_received :directive_validated
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

    refute_received {:signal, %Signal{type: "runtime.record"}}
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
end
