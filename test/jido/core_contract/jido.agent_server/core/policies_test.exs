Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.PoliciesTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Core
  alias Jido.Error.ValidationError
  alias Jido.Tracing.{Context, Trace}
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server.I26"
  test "invalid execution, policy, and history settings fail before startup", c do
    for opts <- [
          [exec_opts: nil],
          [exec_opts: [unknown: 1]],
          [exec_opts: [timeout: -1]],
          [exec_opts: [timeout: 4_294_967_296]],
          [exec_opts: [max_attempts: 0]],
          [exec_opts: [max_concurrency: 0]],
          [exec_opts: [backoff: :invalid]],
          [exec_opts: [base_delay_ms: :infinity]],
          [exec_opts: [max_delay_ms: -1]],
          [exec_opts: [timeout: 10, timeout: 10]],
          [exec_opts: [hooks: [on_dispatch: fn _ -> :ok end]]],
          [exec_opts: [hooks: [on_complete: fn _, _ -> :ok end]]],
          [exec_opts: [hooks: [on_failed: fn _, _ -> :ok end]]],
          [exec_opts: [hooks: [on_idle: fn -> :ok end]]],
          [exec_opts: [hooks: [on_persistence_error: fn _, _ -> :ok end]]],
          [exec_opts: [hooks: [transform_runnables: fn _ -> :ok end]]],
          [exec_opts: [hooks: [unknown: fn -> :ok end]]],
          [exec_opts: [hooks: [on_idle: fn _ -> :ok end, on_idle: fn _ -> :ok end]]],
          [error_policy: :invalid],
          [error_policy: {:max_errors, 0}],
          [error_policy: {:emit_signal, {:pid, target: :bad}}],
          [error_policy_timeout: :infinity],
          [error_policy_timeout: -1],
          [debug: :yes],
          [debug_max_events: 0],
          [debug_max_events: 10_001]
        ] do
      assert {:error, %ValidationError{}} =
               Server.start_link(Keyword.merge([agent: c.agent, runner: c.runner], opts))

      assert {:error, %ValidationError{}} = Server.validate_defaults(opts)
    end

    server =
      F.start(c,
        exec_opts: [hooks: [on_persistence_error: fn _, _, _ -> :ok end]]
      )

    assert :ok = Server.stop(server)
  end

  @tag obligation: "jido.agent_server.I26"
  test "supported execution and failure-policy boundaries validate", _c do
    for exec_opts <- [
          [max_attempts: 1],
          [max_concurrency: 1],
          [backoff: :none],
          [backoff: :linear],
          [backoff: :exponential],
          [backoff: :jitter]
        ] do
      assert :ok = Server.validate_defaults(exec_opts: exec_opts)
    end

    assert :ok = Server.validate_defaults(error_policy: {:max_errors, 1})
    assert :ok = Server.validate_defaults(error_policy: {:emit_signal, {:pid, target: self()}})

    assert {:error, %ValidationError{message: "invalid error_policy Signal destination"}} =
             Server.validate_defaults(error_policy: {:emit_signal, {:pid, target: :bad}})

    assert {:error, %ValidationError{message: "invalid error_policy"}} =
             Server.validate_defaults(error_policy: :invalid)

    assert {:error, %ValidationError{message: "invalid exec_opts"}} =
             Server.validate_defaults(exec_opts: [1])

    assert {:error, %ValidationError{message: "invalid exec_opts"}} =
             Server.validate_defaults(exec_opts: [hooks: [1]])
  end

  @tag obligation: ["jido.agent_server.I27", "jido.agent_server.I28"]
  test "execution policy defaults and hook adapters preserve their exact values", _c do
    assert Core.execution_policy([]) == %{
             timeout_ms: :infinity,
             max_retries: 0,
             backoff: :none,
             base_delay_ms: 500,
             max_delay_ms: 30_000,
             on_failure: :halt,
             retry_if: {Jido.Action.Error, :retryable?, []}
           }

    assert Core.execution_policy(
             timeout: 10,
             max_attempts: 3,
             backoff: :linear,
             base_delay_ms: 20,
             max_delay_ms: 40
           ) == %{
             timeout_ms: 10,
             max_retries: 2,
             backoff: :linear,
             base_delay_ms: 20,
             max_delay_ms: 40,
             on_failure: :halt,
             retry_if: {Jido.Action.Error, :retryable?, []}
           }

    observer = self()
    trace = Trace.new_root()

    hooks =
      Core.execution_hooks(
        [
          on_dispatch: fn runnable, state ->
            send(observer, {:dispatch, runnable, state})
            :dispatched
          end,
          on_idle: fn state ->
            send(observer, {:idle, state})
            :idled
          end,
          transform_runnables: fn runnables, state ->
            send(observer, {:transform, runnables, state})
            [:changed]
          end
        ],
        trace
      )

    Context.clear()
    assert hooks[:on_dispatch].(:runnable, :state) == :dispatched
    assert Context.get() == trace
    assert hooks[:on_idle].(:idle_state) == :idled
    assert hooks[:transform_runnables].([:original], :transform_state) == [:changed]
    assert_received {:dispatch, :runnable, :state}
    assert_received {:idle, :idle_state}
    assert_received {:transform, [:original], :transform_state}
    Context.clear()

    failing = Core.execution_hooks([on_idle: fn _ -> raise "PRIVATE_HOOK" end], nil)

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        assert failing[:on_idle].(:state) == :ok
      end)

    assert logs =~ "AgentServer execution hook failed"
    refute logs =~ "PRIVATE_HOOK"
  end

  @tag obligation: "jido.agent_server.I30"
  test "failure policy selection distinguishes failures, cancellation, and error reports", _c do
    assert Core.next_error_count(:failed, 2) == 3
    assert Core.next_error_count(:cancelled, 2) == 2
    assert Core.next_error_count(:timed_out, 2) == 2

    assert Core.failure_decision(:log_only, 1, "work") == {:complete, :continue}

    assert Core.failure_decision(:stop_on_error, 1, "work") ==
             {:complete, {:stop, :agent_error}}

    assert Core.failure_decision({:max_errors, 2}, 1, "work") == {:complete, :continue}

    assert Core.failure_decision({:max_errors, 2}, 2, "work") ==
             {:complete, {:stop, :max_agent_errors}}

    assert Core.failure_decision(
             {:emit_signal, {:pid, target: self()}},
             1,
             "jido.agent_server.error"
           ) == {:complete, :continue}

    assert Core.failure_decision(fn _, _ -> :continue end, 1, "work") == :run
  end

  @tag obligation: "jido.agent_server.I27"
  test "retryable Action and Flow failures respect attempts and backoff; other errors run once",
       c do
    for type <- ["work", "flow"], retry <- [true, false] do
      counter = start_supervised!(Supervisor.child_spec({Agent, fn -> 0 end}, id: make_ref()))

      server =
        F.start(c,
          exec_opts: [max_attempts: 3, backoff: :linear, base_delay_ms: 25, max_delay_ms: 25]
        )

      result =
        Server.call(server, F.signal(%{mode: :retry, failures: 2, retry: retry}, type),
          context: %{observer: self(), counter: counter}
        )

      assert_receive {:attempt, 1, first}

      if retry do
        assert {:ok, %{state: %{count: 1}}, []} = result
        assert_receive {:attempt, 2, second}
        assert_receive {:attempt, 3, third}
        assert second - first >= 25
        assert third - second >= 25
        assert Agent.get(counter, & &1) == 3
        assert Server.status(server).state_version == 1
      else
        assert {:error, _} = result
        assert Agent.get(counter, & &1) == 1
        F.unchanged(server, c.agent)
      end

      Server.stop(server)
      F.clean(c.runner)
    end
  end

  @tag obligation: "jido.agent_server.I27"
  test "exhausted attempts do not commit and outer timeout stops retry backoff", c do
    for timeout <- [:infinity, 150] do
      counter = start_supervised!(Supervisor.child_spec({Agent, fn -> 0 end}, id: make_ref()))

      server =
        F.start(c,
          turn_timeout: timeout,
          exec_opts: [max_attempts: 2, backoff: :linear, base_delay_ms: 500, max_delay_ms: 500]
        )

      result =
        Server.call(server, F.signal(%{mode: :retry, failures: 10, retry: true}),
          context: %{observer: self(), counter: counter}
        )

      assert {:error, _} = result

      if timeout == :infinity do
        assert Agent.get(counter, & &1) == 2
        assert Server.status(server).last_outcome.status == :failed
      else
        assert result == {:error, :turn_timeout}
        assert Agent.get(counter, & &1) == 1
      end

      F.unchanged(server, c.agent)
      F.clean(c.runner)
      Server.stop(server)
    end
  end

  @tag obligation: ["jido.agent_server.I27", "jido.agent_server.I28"]
  test "per-node timeout stops the Action without using the outer turn deadline", c do
    server = F.start(c, turn_timeout: :infinity, exec_opts: [timeout: 100])
    turn = F.blocked(server, c.runner)
    assert {:error, _} = Server.await(turn.pending, 1_000)
    F.down(turn.action)

    assert %{status: :failed, stage: :running, committed?: false} =
             Server.status(server).last_outcome

    F.unchanged(server, c.agent)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I28"
  test "parallel Flow nodes run together and user hooks compose with owned execution", c do
    observer = self()

    hooks = [
      on_dispatch: fn _, _ -> send(observer, :dispatched) end,
      on_complete: fn _, _, _ -> send(observer, :completed) end
    ]

    server = F.start(c, exec_opts: [max_concurrency: 2, hooks: hooks])

    pending =
      Server.submit(server, F.signal(%{mode: :gate}, "parallel"), context: %{observer: self()})

    assert_receive {:executing, left, _, _}, 1_000
    assert_receive {:executing, right, _, _}, 1_000
    assert left != right
    assert_receive :dispatched
    assert_receive :dispatched
    assert Server.agent(server) == c.agent
    send(left, :release)
    send(right, :release)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending)
    assert_receive :completed
    assert_receive :completed
    assert Server.status(server).state_version == 1
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I27"
  test "cancel during backoff removes pending retry work", c do
    counter = start_supervised!({Agent, fn -> 0 end})

    server =
      F.start(c,
        exec_opts: [max_attempts: 3, backoff: :linear, base_delay_ms: 500, max_delay_ms: 500]
      )

    pending =
      Server.submit(server, F.signal(%{mode: :retry, failures: 10, retry: true}),
        context: %{observer: self(), counter: counter}
      )

    assert_receive {:attempt, 1, _}, 1_000
    assert :ok = Server.cancel(server)
    assert {:error, :cancelled} = Server.await(pending)
    assert Agent.get(counter, & &1) == 1
    F.unchanged(server, c.agent)
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server.I28", "jido.agent_server.I25"]
  test "hook exceptions do not disclose raw values or prevent cleanup", c do
    observer = self()

    hooks = [
      on_dispatch: fn _, _ -> raise "PRIVATE_HOOK_DISPATCH" end,
      on_failed: fn _, _, _ ->
        send(observer, :failure_hook)
        throw("PRIVATE_HOOK_ERROR")
      end,
      on_complete: fn _, _, _ -> exit("PRIVATE_HOOK_COMPLETE") end,
      on_idle: fn _ -> raise "PRIVATE_HOOK_IDLE" end,
      transform_runnables: fn _, _ -> raise "PRIVATE_HOOK_TRANSFORM" end
    ]

    server = F.start(c, exec_opts: [hooks: hooks])

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, _} = Server.call(server, F.signal(%{mode: :fail}))
        assert_receive :failure_hook
        assert {:ok, _, []} = Server.call(server, F.signal())
      end)

    refute logs =~ "PRIVATE_HOOK"
    assert Server.status(server).state_version == 1
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I30"
  test "stop and consecutive error threshold preserve the original error reply", c do
    stop = F.start(c, error_policy: :stop_on_error)
    ref = Process.monitor(stop)
    assert {:error, _} = Server.call(stop, F.signal(%{mode: :fail}))
    assert_receive {:DOWN, ^ref, :process, ^stop, {:shutdown, :agent_error}}

    server = F.start(c, error_policy: {:max_errors, 2})
    assert {:error, _} = Server.call(server, F.signal(%{mode: :fail}))
    assert Server.status(server).error_count == 1
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert Server.status(server).error_count == 0
    assert {:error, _} = Server.call(server, F.signal(%{mode: :fail}))
    assert Server.status(server).error_count == 1
    ref = Process.monitor(server)
    assert {:error, _} = Server.call(server, F.signal(%{mode: :fail}))
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :max_agent_errors}}
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I31"
  test "bounded callbacks keep reads available and cannot start reentrant work", c do
    observer = self()

    policy = fn error, outcome ->
      send(observer, {:policy, self(), error, outcome})

      receive do
        {:probe, server} ->
          send(observer, {:policy_probe, Server.call(server, F.signal())})
      end

      receive do
        :release -> :continue
      end
    end

    server = F.start(c, error_policy: policy, error_policy_timeout: 1_000)
    pending = Server.submit(server, F.signal(%{mode: :fail}))
    assert_receive {:policy, task, error, %{status: :failed, committed?: false}}, 1_000
    assert inspect(error) =~ "SERVER2_PRIVATE_ERROR"
    assert Server.agent(server) == c.agent
    assert Server.status(server).active.stage == :policy
    send(task, {:probe, server})
    assert_receive {:policy_probe, {:error, :reentrant_turn}}
    queued = Server.submit(server, F.signal())
    assert {:error, :timeout} = Server.await(queued, 0)
    send(task, :release)
    assert {:error, ^error} = Server.await(pending)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(queued)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.I31"
  test "callback timeout, raise, and invalid decision stop safely with the original error", c do
    for {policy, reason} <- [
          {fn _, _ ->
             receive do
               :never -> :continue
             end
           end, :error_policy_timeout},
          {fn _, _ -> raise "private callback failure" end, :error_policy_failed},
          {fn _, _ -> :bad end, :invalid_error_policy_result},
          {fn _, _ -> {:stop, :custom} end, :custom}
        ] do
      server = F.start(c, error_policy: policy, error_policy_timeout: 100)
      ref = Process.monitor(server)
      assert {:error, error} = Server.call(server, F.signal(%{mode: :fail}))
      assert inspect(error) =~ "SERVER2_PRIVATE_ERROR"
      assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, ^reason}}, 1_000
      F.clean(c.runner)
    end
  end

  @tag obligation: "jido.agent_server.I31"
  test "a callback result queued before its timer cannot bypass the elapsed deadline", c do
    observer = self()

    policy = fn _, _ ->
      send(observer, {:policy_task, self()})

      receive do
        :release -> :continue
      end
    end

    server = F.start(c, error_policy: policy, error_policy_timeout: 150)
    ref = Process.monitor(server)
    pending = Server.submit(server, F.signal(%{mode: :fail}))
    assert_receive {:policy_task, task}, 1_000
    :ok = :sys.suspend(server)
    on_exit(fn -> if Process.alive?(server), do: :sys.resume(server) end)
    send(task, :release)
    F.down(task)
    F.elapsed(170)
    :ok = :sys.resume(server)
    assert {:error, error} = Server.await(pending)
    assert inspect(error) =~ "SERVER2_PRIVATE_ERROR"
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :error_policy_timeout}}, 1_000
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server.I31", "jido.agent_server.I29"]
  test "killed policy task retains the original terminal error and emits one outcome", c do
    observer = self()

    policy = fn _, _ ->
      send(observer, {:policy_task, self()})

      receive do
        :never -> :continue
      end
    end

    server = F.start(c, debug: true, error_policy: policy)
    ref = Process.monitor(server)
    pending = Server.submit(server, F.signal(%{mode: :fail}))
    assert_receive {:policy_task, task}, 1_000
    assert length(Server.history(server)) == 1
    Process.exit(task, :kill)
    assert {:error, error} = Server.await(pending)
    assert inspect(error) =~ "SERVER2_PRIVATE_ERROR"
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :error_policy_failed}}, 1_000
    F.clean(c.runner)
  end
end
