Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Durability.RunInspectionTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/03_durability/03_07_run_inspection/run_inspection.ex")

    :ok
  end

  test "distinguishes active and complete managed work" do
    runner = Module.concat(__MODULE__, Runner)
    observer = Module.concat(__MODULE__, Observer)
    Process.register(self(), observer)
    start_supervised!({Runic.Runner, name: runner})
    id = {:inspection, System.unique_integer([:positive])}
    gate = "inspection-#{System.unique_integer([:positive])}"
    owner = self()

    assert {:ok, _worker} =
             Jido.Exec.start(
               runner,
               id,
               Jido.Examples.Durability.RunInspection,
               %{value: 8},
               %{gate: gate, observer: observer},
               hooks: [on_idle: fn _state -> send(owner, :idle) end]
             )

    assert_receive {:inspection_waiting, task}, 1_000

    assert {:ok, %{active_units: 1, status: :open}} =
             Runic.Runner.admission_status(runner, id)

    assert {:ok, %Runic.Workflow{}} = Runic.Runner.get_workflow(runner, id)

    assert {:error, %Jido.Error.ExecutionError{details: %{reason: :execution_active}}} =
             Jido.Exec.result(runner, id)

    send(task, {:release_inspection, gate})
    assert_receive :idle, 1_000
    assert Jido.Exec.result(runner, id) == {:ok, %{value: 9}}
  end
end
