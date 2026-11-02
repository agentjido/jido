defmodule Jido.Exec.Runner.StepwiseTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I21"

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Runic.Workflow

  defmodule Recorder do
    use Agent

    def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(label), do: Agent.update(__MODULE__, &(&1 ++ [label]))
    def entries, do: Agent.get(__MODULE__, & &1)
  end

  defmodule RecordAdd do
    use Jido.Action, name: "stepwise_record_add"

    @impl true
    def run(%{label: label, value: value}, _context) do
      :ok = Recorder.record(label)
      {:ok, %{value: value + 1}}
    end
  end

  defmodule Fail do
    use Jido.Action, name: "stepwise_fail"

    @impl true
    def run(_params, _context) do
      :ok = Recorder.record(:failed)
      {:error, :step_failed}
    end
  end

  defmodule Controlled do
    use Jido.Action, name: "stepwise_controlled"

    @impl true
    def run(%{label: label, fail: fail}, %{observer: observer}) do
      send(Process.whereis(observer), {:started, label, self()})

      receive do
        :release -> if fail, do: {:error, :controlled_failure}, else: {:ok, %{value: 1}}
      end
    end
  end

  setup do
    runner = Module.concat(__MODULE__, Runner)
    start_supervised!(Recorder)
    start_supervised!({Runic.Runner, name: runner})
    %{runner: runner}
  end

  test "automatic dispatch remains the default", %{runner: runner} do
    flow = serial_flow("automatic_stepwise_default")
    execution_id = {:automatic, System.unique_integer([:positive])}
    tag = make_ref()

    assert {:ok, _pid} =
             Exec.start(runner, execution_id, flow, %{value: 0}, %{}, hooks: runner_hooks(tag))

    assert {:error, :automatic_dispatch} = Exec.step(runner, execution_id)
    assert_receive {^tag, :idle}, 1_000

    assert {:ok, productions} = Runic.Runner.get_results(runner, execution_id)
    assert %{value: 2} in productions
    assert Recorder.entries() == [:first, :second]
  end

  test "a caller advances one Runic unit and inspects the workflow until completion", %{
    runner: runner
  } do
    flow = serial_flow("manual_stepwise_flow")
    execution_id = {:manual, System.unique_integer([:positive])}
    tag = make_ref()

    assert {:ok, _pid} =
             Exec.start(runner, execution_id, flow, %{value: 0}, %{},
               dispatch_mode: :manual,
               max_concurrency: 1,
               hooks: runner_hooks(tag)
             )

    assert {3, %Workflow{} = workflow} = step_to_completion(runner, execution_id, tag)
    refute Workflow.is_runnable?(workflow)
    assert Exec.result(runner, execution_id) == {:ok, %{value: 2}}
    assert Recorder.entries() == [:first, :second]

    assert {:ok, productions} = Runic.Runner.get_results(runner, execution_id)
    assert %{value: 2} in productions
  end

  test "a failed unit returns terminal Runic state and blocks dependent work", %{runner: runner} do
    flow = failure_flow()
    execution_id = {:failure, System.unique_integer([:positive])}
    tag = make_ref()

    assert {:ok, _pid} =
             Exec.start(runner, execution_id, flow, %{}, %{},
               dispatch_mode: :manual,
               hooks: runner_hooks(tag)
             )

    assert {_steps, %Workflow{}} = step_to_completion(runner, execution_id, tag)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: "step_failed"}} =
             Exec.result(runner, execution_id)

    assert Recorder.entries() == [:failed]
  end

  test "stopped admission stays busy until already admitted work completes", %{runner: runner} do
    observer = Module.concat(__MODULE__, Observer)
    Process.register(self(), observer)
    owner = self()
    id = {:active_failure, System.unique_integer([:positive])}

    flow =
      Flow.new!(%{
        name: "active_failure",
        components: [
          %{kind: :step, name: "a", action: Controlled, params: %{label: :a, fail: true}},
          %{kind: :step, name: "b", action: Controlled, params: %{label: :b, fail: false}}
        ],
        output: %{a: Ref.result("a"), b: Ref.result("b")}
      })

    assert {:ok, _worker} =
             Exec.start(runner, id, flow, %{}, %{observer: observer},
               max_concurrency: 2,
               hooks: [
                 on_failed: fn _runnable, _reason, _state -> send(owner, :failed) end,
                 on_idle: fn _state -> send(owner, :idle) end
               ]
             )

    assert_receive {:started, :a, a}, 1_000
    assert_receive {:started, :b, b}, 1_000
    send(a, :release)
    assert_receive :failed, 1_000
    assert Exec.step(runner, id) == {:error, :busy}

    send(b, :release)
    assert_receive :idle, 1_000
    assert {:complete, %Workflow{}} = Exec.step(runner, id)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: "controlled_failure"}} =
             Exec.result(runner, id)
  end

  test "manual execution resumes from durable Runic state", %{runner: runner} do
    flow = serial_flow("durable_stepwise_flow")
    execution_id = {:durable_manual, System.unique_integer([:positive])}
    tag = make_ref()

    assert {:ok, _pid} =
             Exec.start(runner, execution_id, flow, %{value: 0}, %{},
               dispatch_mode: :manual,
               max_concurrency: 1,
               checkpoint_strategy: :every_cycle,
               hooks: runner_hooks(tag)
             )

    assert {:ok, %Workflow{} = workflow} = Exec.step(runner, execution_id)
    first_hash = Workflow.get_component(workflow, "first").hash
    assert_receive {^tag, :unit_done, ^first_hash}, 1_000
    assert Recorder.entries() == [:first]

    assert :ok = Runic.Runner.checkpoint(runner, execution_id)
    assert :ok = Runic.Runner.stop(runner, execution_id, persist: true)

    assert {:ok, _pid} =
             Runic.Runner.resume(runner, execution_id,
               dispatch_mode: :manual,
               max_concurrency: 1,
               hooks: runner_hooks(tag)
             )

    assert {_steps, %Workflow{}} = step_to_completion(runner, execution_id, tag)
    assert Recorder.entries() == [:first, :second]

    assert {:ok, productions} = Runic.Runner.get_results(runner, execution_id)
    assert %{value: 2} in productions
  end

  defp serial_flow(name) do
    Flow.new!(%{
      name: name,
      components: [
        %{
          kind: :step,
          name: "first",
          action: RecordAdd,
          params: %{label: :first, value: Ref.input(:value)}
        },
        %{
          kind: :step,
          name: "second",
          action: RecordAdd,
          params: %{label: :second, value: Ref.result("first", :value)}
        }
      ],
      output: Ref.result("second")
    })
  end

  defp failure_flow do
    Flow.new!(%{
      name: "manual_stepwise_failure",
      components: [
        %{kind: :step, name: "fail", action: Fail, params: %{}},
        %{
          kind: :step,
          name: "blocked",
          action: RecordAdd,
          params: %{label: :blocked, value: Ref.result("fail", :value)}
        }
      ],
      output: Ref.result("blocked")
    })
  end

  # Runic calls these hooks in the Worker before it handles the next call, so
  # each message is a barrier for the next step.
  defp runner_hooks(tag) do
    test_pid = self()

    [
      on_complete: fn runnable, _duration, _state ->
        send(test_pid, {tag, :unit_done, runnable.node.hash})
      end,
      on_failed: fn runnable, _reason, _state ->
        send(test_pid, {tag, :unit_done, runnable.node.hash})
      end,
      on_idle: fn _state -> send(test_pid, {tag, :idle}) end
    ]
  end

  defp step_to_completion(runner, execution_id, tag, count \\ 0) do
    case Exec.step(runner, execution_id) do
      {:ok, %Workflow{}} ->
        assert_receive {^tag, :unit_done, _node_hash}, 1_000
        step_to_completion(runner, execution_id, tag, count + 1)

      {:complete, %Workflow{} = workflow} ->
        {count, workflow}
    end
  end
end
