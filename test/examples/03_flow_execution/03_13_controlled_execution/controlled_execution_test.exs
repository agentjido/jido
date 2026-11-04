Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.ControlledExecutionTest do
  use ExUnit.Case, async: false
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("03_flow_execution/03_13_controlled_execution/controlled_execution.ex")
    :ok
  end

  test "immediate and manual managed execution return equal output" do
    module = Jido.Examples.Execution.ControlledExecution
    expected = %{left: %{value: 12}, right: %{value: 22}}
    assert Jido.Exec.run(module, %{value: 1}) == {:ok, expected}

    runner = Module.concat(__MODULE__, Runner)
    start_supervised!({Runic.Runner, name: runner})
    id = "example-controlled-#{System.unique_integer([:positive])}"
    tag = make_ref()
    test_pid = self()

    hooks = [
      on_complete: fn _runnable, _duration, _state -> send(test_pid, {tag, :unit_done}) end,
      on_failed: fn _runnable, _reason, _state -> send(test_pid, {tag, :unit_done}) end
    ]

    assert {:ok, _pid} =
             Jido.Exec.start(runner, id, module, %{value: 1}, %{},
               dispatch_mode: :manual,
               max_concurrency: 1,
               hooks: hooks
             )

    assert %Runic.Workflow{} = step_to_completion(runner, id, tag)
    assert Jido.Exec.result(runner, id) == {:ok, expected}
  end

  defp step_to_completion(runner, id, tag) do
    case Jido.Exec.step(runner, id) do
      {:ok, %Runic.Workflow{}} ->
        assert_receive {^tag, :unit_done}, 1_000
        step_to_completion(runner, id, tag)

      {:complete, %Runic.Workflow{} = workflow} ->
        workflow
    end
  end
end
