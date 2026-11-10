Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Durability.ProcessRecoveryTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("05_flow_durability/05_03_process_recovery/process_recovery.ex")

    :ok
  end

  test "restores pending work without repeating completed work" do
    runner = Module.concat(__MODULE__, Runner)
    observer = Module.concat(__MODULE__, Observer)
    Process.register(self(), observer)
    start_supervised!({Runic.Runner, name: runner})
    id = {:process_recovery, System.unique_integer([:positive])}
    gate = "gate-#{System.unique_integer([:positive])}"
    owner = self()
    context = %{gate: gate, observer: observer}
    hooks = [on_idle: fn _state -> send(owner, :idle) end]

    assert {:ok, worker} =
             Jido.Test.Exec.RunnerHarness.start(
               runner,
               id,
               Jido.Examples.Durability.ProcessRecovery,
               %{value: 4},
               context,
               hooks: hooks
             )

    assert_receive :recovery_recorded, 1_000
    assert_receive {:recovery_waiting, task}, 1_000
    worker_monitor = Process.monitor(worker)
    task_monitor = Process.monitor(task)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _reason}, 1_000
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _reason}, 1_000

    assert {:ok, _worker} = Jido.Test.Exec.RunnerHarness.resume(runner, id, context, hooks: hooks)
    assert_receive {:recovery_waiting, resumed_task}, 1_000
    refute resumed_task == task
    refute_received :recovery_recorded
    send(resumed_task, {:release_recovery, gate})
    assert_receive :idle, 1_000
    assert Jido.Test.Exec.RunnerHarness.result(runner, id) == {:ok, %{value: 6}}
  end
end
