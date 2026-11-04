Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Durability.CancellationTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("05_flow_durability/05_05_cancellation/cancellation.ex")

    :ok
  end

  test "stops active items and admits no later item" do
    runner = Module.concat(__MODULE__, Runner)
    observer = Module.concat(__MODULE__, Observer)
    Process.register(self(), observer)
    start_supervised!({Runic.Runner, name: runner})
    id = {:cancellation, System.unique_integer([:positive])}
    gate = "cancel-#{System.unique_integer([:positive])}"

    assert {:ok, worker} =
             Jido.Exec.start(
               runner,
               id,
               Jido.Examples.Durability.Cancellation,
               %{items: [:a, :b, :c]},
               %{gate: gate, observer: observer},
               max_concurrency: 2
             )

    assert_receive {:cancellation_waiting, :a, a}, 1_000
    assert_receive {:cancellation_waiting, :b, b}, 1_000
    monitors = for process <- [worker, a, b], do: {process, Process.monitor(process)}
    assert :ok = Runic.Runner.cancel(runner, id)

    for {process, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^process, _reason}, 1_000
    end

    refute_received {:cancellation_waiting, :c, _task}
    assert Runic.Runner.admission_status(runner, id) == {:error, :not_found}
  end
end
