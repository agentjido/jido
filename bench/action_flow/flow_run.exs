Code.require_file("support.exs", __DIR__)
Code.require_file("fixtures.exs", __DIR__)

defmodule Jido.Bench.ActionFlow.FlowRun do
  @moduledoc false

  alias Jido.Bench.ActionFlow.{Fixtures, Identity, StaticFlow, Support}

  @profiles %{
    "quick" => %{width: 4, samples: 3, warmup: 1},
    "standard" => %{width: 16, samples: 15, warmup: 3},
    "stress" => %{width: 64, samples: 30, warmup: 5}
  }

  def main(argv) do
    options = Support.options!(argv, "flow_run")
    settings = Support.profile!(options.profile, @profiles)
    baseline = Support.task_children()
    wide = Fixtures.wide_flow(settings.width)

    cases =
      [
        {"action", fn -> Jido.Exec.run(Identity, %{value: 7}) end},
        {"flow_module", fn -> Jido.Exec.run(StaticFlow, %{value: 7}) end},
        {"flow_value", fn -> Jido.Exec.run(wide, %{value: 7}) end}
      ]
      |> Enum.map(fn {name, operation} ->
        Support.measure!(name, operation, &check_result!(&1, baseline), settings)
      end)

    after_run = Support.task_children()

    Support.report!("jido.action_flow.run", options, settings, cases, %{
      cleanup: %{
        task_children_before: MapSet.size(baseline),
        task_children_after: MapSet.size(after_run)
      }
    })
  end

  defp check_result!({:ok, %{value: 7}}, baseline) do
    Support.await_task_children!(baseline)
    :ok
  end

  defp check_result!(result, _baseline),
    do: raise("incorrect execution result: #{inspect(result)}")
end

Jido.Bench.ActionFlow.FlowRun.main(System.argv())
