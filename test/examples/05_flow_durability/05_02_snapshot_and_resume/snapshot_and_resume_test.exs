Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Durability.SnapshotAndResumeTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("05_flow_durability/05_02_snapshot_and_resume/snapshot_and_resume.ex")

    :ok
  end

  test "restores a checkpoint without repeating completed Actions" do
    runner = Module.concat(__MODULE__, Runner)
    observer = Module.concat(__MODULE__, Observer)
    Process.register(self(), observer)
    start_supervised!({Runic.Runner, name: runner})
    id = {:snapshot, System.unique_integer([:positive])}
    owner = self()
    hooks = [on_idle: fn _state -> send(owner, :idle) end]

    assert {:ok, _worker} =
             Jido.Exec.start(
               runner,
               id,
               Jido.Examples.Durability.SnapshotAndResume,
               %{value: 3},
               %{observer: observer},
               hooks: hooks
             )

    assert_receive {:snapshot_step, 1}, 1_000
    assert_receive {:snapshot_step, 2}, 1_000
    assert_receive :idle, 1_000
    assert Jido.Exec.result(runner, id) == {:ok, %{value: 5}}
    assert :ok = Runic.Runner.checkpoint(runner, id)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)

    assert {:ok, _worker} =
             Jido.Exec.resume(runner, id, %{observer: observer}, hooks: hooks)

    assert Jido.Exec.result(runner, id) == {:ok, %{value: 5}}
    refute_received {:snapshot_step, _step}
  end
end
