defmodule JidoTest.Examples.Workflow.BoundedIterationTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.BoundedIteration, as: Example

  test "initial completion skips the body and the final allowed repair succeeds", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, command_signal_1} = Example.repair_signal(%{missing: 0})

    assert {:ok, complete} =
             Server.call(
               server,
               command_signal_1
             )

    assert complete.state.result == %{iterations: 0, state: %{missing: 0, repairs: 0}}

    {:ok, command_signal_2} = Example.repair_signal(%{missing: 3})

    assert {:ok, repaired} =
             Server.call(
               server,
               command_signal_2
             )

    assert repaired.state.result == %{iterations: 3, state: %{missing: 0, repairs: 3}}
    assert Server.snapshot(server) == %{agent: repaired, state_version: 2}
  end

  test "iteration exhaustion preserves the prior result", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, command_signal_3} = Example.repair_signal(%{missing: 1})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_3
             )

    before = Server.snapshot(server)

    {:ok, command_signal_4} = Example.repair_signal(%{missing: 4})

    assert {:error, error} =
             Server.call(
               server,
               command_signal_4
             )

    assert Enum.any?(errors(error), &(&1.type == :flow_execution_error))
    assert Server.snapshot(server) == before
  end

  test "Flow input and replacement state validation have separate errors", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)

    {:ok, command_signal_5} = Example.repair_signal(%{missing: -1})

    assert {:error, %Jido.Flow.Error.InvalidExecutionError{details: %{phase: :flow_input}}} =
             Server.call(
               server,
               command_signal_5
             )

    {:ok, command_signal_6} = Example.repair_signal(%{missing: 1, repair_size: 2})

    assert {:error,
            %Jido.Flow.Error.InvalidExecutionError{details: %{phase: :iterate_state_update}}} =
             Server.call(
               server,
               command_signal_6
             )

    assert Server.snapshot(server) == before
  end
end
