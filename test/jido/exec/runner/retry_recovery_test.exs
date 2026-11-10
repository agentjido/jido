defmodule Jido.Exec.Runner.RetryRecoveryTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  alias Jido.Exec

  defmodule LostReplyStore do
    @behaviour Runic.Runner.Store
    def init_store(opts), do: {:ok, Keyword.fetch!(opts, :agent)}

    def save(id, log, agent) do
      Agent.get_and_update(agent, fn state ->
        reply = if state.lose?, do: {:error, :lost_reply}, else: :ok
        {reply, %{state | logs: Map.put(state.logs, id, log), lose?: false}}
      end)
    end

    def load(id, agent) do
      Agent.get(agent, fn state ->
        case Map.fetch(state.logs, id) do
          {:ok, log} -> {:ok, log}
          :error -> {:error, :not_found}
        end
      end)
    end
  end

  defmodule CompletedStep do
    use Jido.Action, name: "completed_before_failure"

    def run(_, %{counter: counter}) do
      Agent.update(counter, &Map.update!(&1, :completed, fn count -> count + 1 end))
      {:ok, %{done: true}}
    end
  end

  defmodule TerminalFailure do
    use Jido.Action, name: "terminal_failure"

    def run(_, %{counter: counter}) do
      Agent.update(counter, &Map.update!(&1, :attempt, fn count -> count + 1 end))
      {:error, Jido.Error.execution_error("terminal", %{retry: false})}
    end
  end

  defmodule Probe do
    use Jido.Action, name: "retry_recovery_probe"

    def run(%{trace_delay: trace_delay}, %{counter: counter}) do
      {attempt, owner} =
        Agent.get_and_update(counter, fn state ->
          {{state.attempt + 1, state.owner}, %{state | attempt: state.attempt + 1}}
        end)

      if trace_delay, do: :erlang.trace(self(), true, [:call, {:tracer, owner}])
      send(owner, {:attempt, attempt, self()})

      unless trace_delay do
        receive do
          {:release, ^attempt} -> :ok
        end
      end

      {:error, Jido.Error.execution_error("retry probe", %{retry: true})}
    end
  end

  setup do
    owner = self()

    start_supervised!(%{
      id: __MODULE__.Counter,
      start: {Agent, :start_link, [fn -> %{attempt: 0, completed: 0, owner: owner} end, [name: __MODULE__.Counter]]}
    })

    runner = __MODULE__.Runner
    start_supervised!({Runic.Runner, name: runner})
    %{runner: runner}
  end

  test "a lost save reply does not repeat completed work or a non-retryable failure" do
    store = start_supervised!({Agent, fn -> %{logs: %{}, lose?: false} end})
    runner = __MODULE__.LostReplyRunner

    start_supervised!(
      Supervisor.child_spec(
        {Runic.Runner, name: runner, store: LostReplyStore, store_opts: [agent: store]},
        id: runner
      )
    )

    flow =
      Jido.Flow.new!(%{
        name: "terminal_recovery",
        components: [
          %{kind: :step, name: "completed", action: CompletedStep},
          %{kind: :step, name: "failed", action: TerminalFailure, needs: ["completed"]}
        ],
        output: Jido.Flow.Ref.result("failed")
      })

    owner = self()
    opts = [max_attempts: 3, on_complete: fn _, _ -> send(owner, :terminal_complete) end]
    context = %{counter: __MODULE__.Counter}
    assert {:ok, worker} = Exec.start(runner, "lost-reply", flow, %{}, context, opts)
    assert_receive :terminal_complete, 2_000
    assert {:error, %{message: "terminal"}} = Exec.result(runner, "lost-reply")
    Agent.update(store, &%{&1 | lose?: true})

    assert {:error, {:persistence_failed, :lost_reply}} =
             Runic.Runner.stop(runner, "lost-reply", persist: true)

    assert Process.alive?(worker)
    assert {:ok, _saved} = LostReplyStore.load("lost-reply", store)
    assert {:ok, persistence} = Runic.Runner.persistence_status(runner, "lost-reply")
    assert persistence.status == {:error, {:persistence_failed, :lost_reply}}
    assert :ok = Runic.Runner.stop(runner, "lost-reply", persist: true)
    assert {:ok, _} = Exec.resume(runner, "lost-reply", context, opts)
    assert {:error, %{message: "terminal"}} = Exec.result(runner, "lost-reply")
    assert %{attempt: 1, completed: 1} = Agent.get(__MODULE__.Counter, & &1)
  end

  test "an unaccepted retry budget resets on restore, while accepted terminal failure stays terminal",
       %{runner: runner} do
    id = "retry-budget"
    opts = [max_attempts: 2]
    context = %{counter: __MODULE__.Counter}
    assert {:ok, _worker} = Exec.start(runner, id, Probe, %{trace_delay: false}, context, opts)
    assert_receive {:attempt, 1, task}, 2_000
    send(task, {:release, 1})
    assert_receive {:attempt, 2, ^task}, 2_000
    assert {:ok, %{active_units: 1}} = Runic.Runner.admission_status(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    owner = self()
    opts = Keyword.put(opts, :on_complete, fn _, _ -> send(owner, :completed) end)
    assert {:ok, _worker} = Exec.resume(runner, id, context, opts)
    assert_receive {:attempt, 3, resumed}, 2_000
    refute resumed == task
    send(resumed, {:release, 3})
    assert_receive {:attempt, 4, ^resumed}, 2_000
    send(resumed, {:release, 4})
    assert_receive :completed, 2_000
    assert {:error, %{message: "retry probe"}} = Exec.result(runner, id)
    assert {:ok, %{status: :stopped}} = Runic.Runner.admission_status(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    assert {:ok, _worker} = Exec.resume(runner, id, context, opts)
    assert {:error, %{message: "retry probe"}} = Exec.result(runner, id)
    assert Agent.get(__MODULE__.Counter, & &1.attempt) == 4
    refute_received {:attempt, _, _}
  end

  test "backoff retains a task, has no durable deadline, and cancellation stops it", %{
    runner: runner
  } do
    :erlang.trace_pattern({Process, :sleep, 1}, true, [:local])
    on_exit(fn -> :erlang.trace_pattern({Process, :sleep, 1}, false, [:local]) end)
    id = "backoff"
    context = %{counter: __MODULE__.Counter}

    opts = [
      max_attempts: 2,
      backoff: :linear,
      base_delay_ms: 86_400_000,
      max_delay_ms: 86_400_000
    ]

    assert {:ok, _worker} = Exec.start(runner, id, Probe, %{trace_delay: true}, context, opts)
    assert_receive {:attempt, 1, task}, 2_000
    assert_receive {:trace, ^task, :call, {Process, :sleep, [86_400_000]}}, 2_000
    monitor = Process.monitor(task)
    assert {:ok, %{active_units: 1}} = Runic.Runner.admission_status(runner, id)
    assert :ok = Runic.Runner.checkpoint(runner, id)
    {store, state} = Runic.Runner.get_store(runner)
    assert {:ok, events} = store.stream(id, state)

    refute Enum.any?(events, fn event ->
             is_map(event) and
               (Map.has_key?(event, :retry_deadline) or Map.has_key?(event, :next_retry_at))
           end)

    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    assert_receive {:DOWN, ^monitor, :process, ^task, _}, 2_000
    assert {:ok, _} = Exec.resume(runner, id, context, opts)
    assert_receive {:attempt, 2, resumed}, 2_000
    assert_receive {:trace, ^resumed, :call, {Process, :sleep, [86_400_000]}}, 2_000
    monitor = Process.monitor(resumed)
    assert :ok = Runic.Runner.cancel(runner, id)
    assert_receive {:DOWN, ^monitor, :process, ^resumed, _}, 2_000
    assert {:error, :not_found} = Runic.Runner.admission_status(runner, id)
    assert Agent.get(__MODULE__.Counter, & &1.attempt) == 2
  end
end
