Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.ParallelTest do
  use ExUnit.Case, async: false
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_07_parallel/parallel.ex")
    :ok
  end

  test "message barriers prove bounded concurrency and exact keyed results" do
    {:ok, probe} = Agent.start_link(fn -> %{active: 0, max_active: 0, started: []} end)
    on_exit(fn -> if Process.alive?(probe), do: Agent.stop(probe) end)
    gate = make_ref()
    parent = self()

    task =
      Task.async(fn ->
        Jido.Exec.run(
          Jido.Examples.Execution.Parallel,
          %{left: 1, middle: 2, right: 3},
          %{observer: parent, gate: gate, probe: probe},
          max_concurrency: 2
        )
      end)

    first =
      for _ <- 1..2 do
        assert_receive {:parallel_ready, name, worker}
        {name, worker}
      end

    assert Agent.get(probe, & &1.max_active) == 2
    Enum.each(first, fn {_name, worker} -> send(worker, {:release_parallel, gate}) end)
    assert_receive {:parallel_ready, third, worker}
    assert third not in Enum.map(first, &elem(&1, 0))
    send(worker, {:release_parallel, gate})

    assert Task.await(task) ==
             {:ok,
              %{
                checks: %{
                  "left" => %{name: "left", value: 2},
                  "middle" => %{name: "middle", value: 4},
                  "right" => %{name: "right", value: 6}
                }
              }}

    assert Agent.get(probe, & &1.active) == 0
  end
end
