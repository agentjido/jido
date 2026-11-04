Code.require_file("../support/runner.exs", __DIR__)
Code.require_file("../support/action_flow_fixtures.exs", __DIR__)

defmodule Jido.Test.Perf.Exec.FlowRun do
  @moduledoc false

  alias Jido.Test.Perf.Flow.{Fixtures, Identity, StaticFlow}
  alias Jido.Test.Perf.Runner

  @profiles %{
    "quick" => %{width: 4, samples: 3, warmup: 1},
    "standard" => %{width: 16, samples: 15, warmup: 3},
    "stress" => %{width: 64, samples: 30, warmup: 5}
  }

  def main(argv) do
    options = Runner.options!(argv, "flow_run")
    settings = Runner.profile!(options.profile, @profiles)
    baseline = Runner.task_children()
    wide = Fixtures.wide_flow(settings.width)

    cases =
      [
        {"action", fn -> Jido.Exec.run(Identity, %{value: 7}) end},
        {"flow_module", fn -> Jido.Exec.run(StaticFlow, %{value: 7}) end},
        {"flow_value", fn -> Jido.Exec.run(wide, %{value: 7}) end}
      ]
      |> Enum.map(fn {name, operation} ->
        Runner.measure!(name, operation, &check_result!(&1, baseline), settings)
      end)

    after_run = Runner.task_children()

    Runner.report!("jido.action_flow.run", options, settings, cases, %{
      cleanup: %{
        task_children_before: MapSet.size(baseline),
        task_children_after: MapSet.size(after_run)
      }
    })
  end

  defp check_result!({:ok, %{value: 7}}, baseline) do
    Runner.await_task_children!(baseline)
    :ok
  end

  defp check_result!(result, _baseline),
    do: raise("incorrect execution result: #{inspect(result)}")
end

Jido.Test.Perf.Exec.FlowRun.main(System.argv())
