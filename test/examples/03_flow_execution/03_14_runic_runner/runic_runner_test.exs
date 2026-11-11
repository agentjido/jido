Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.RunicRunnerTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_14_runic_runner/runic_runner.ex")
    :ok
  end

  test "Runic Runner can dispatch one compiled workflow unit at a time" do
    flow = Jido.Examples.Execution.RunicRunner
    expected = %{left: %{value: 12}, right: %{value: 22}}
    assert Jido.Exec.run(flow, %{value: 1}) == {:ok, expected}

    runner = Module.concat(__MODULE__, Runner)
    start_supervised!({Runic.Runner, name: runner})
    id = "example-runner-#{System.unique_integer([:positive])}"
    tag = make_ref()
    owner = self()

    hooks = [
      on_complete: fn _runnable, _duration, _state -> send(owner, {tag, :unit_done}) end,
      on_failed: fn _runnable, _reason, _state -> send(owner, {tag, :unit_done}) end
    ]

    assert {:ok, instruction} = Jido.Instruction.resolve(flow, %{value: 1})
    assert {:ok, workflow} = Jido.Exec.compile(instruction, [])

    assert {:ok, _pid} =
             Runic.Runner.start_workflow(runner, id, workflow,
               dispatch_mode: :manual,
               max_concurrency: 1,
               hooks: hooks
             )

    execution_id = Runic.Identity.digest(:execution, id)

    assert {:ok, ^execution_id} =
             Runic.Runner.start_execution(
               runner,
               id,
               Jido.Exec.Fact.local_value(instruction.params),
               execution_id: execution_id,
               run_context: %{_global: instruction.context}
             )

    assert %Runic.Workflow{} = workflow = step_to_completion(runner, id, tag)
    assert {:ok, observation} = Runic.Runner.execution(runner, id, execution_id)
    assert Jido.Exec.result(workflow, observation) == {:ok, expected}
  end

  defp step_to_completion(runner, id, tag) do
    case Runic.Runner.step(runner, id) do
      :ok ->
        assert_receive {^tag, :unit_done}, 1_000
        step_to_completion(runner, id, tag)

      {:error, :not_runnable} ->
        {:ok, workflow} = Runic.Runner.get_workflow(runner, id)
        workflow
    end
  end
end
