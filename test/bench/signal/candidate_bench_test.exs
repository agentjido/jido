Code.require_file("support/suite.exs", __DIR__)

defmodule JidoTest.Bench.Signal.CandidateBenchTest do
  use ExUnit.Case, async: false
  @moduletag :bench
  alias Jido.Bench.Signal.{CandidateCases, Measure, Suite}

  test "all six candidate groups check results and clean up processes" do
    workloads = CandidateCases.workloads(2)

    for group <- ~w(utf8 term publish replay remove retention) do
      assert Enum.any?(workloads, &String.starts_with?(&1.name, "candidate/#{group}/"))
    end

    for workload <- workloads do
      assert length(Measure.timing(workload, 1, 1).wall_ns.samples) == 1
      assert Measure.resources(workload).owned_remaining == 0
      activity = Measure.activity(workload)
      assert activity.caller.reductions > 0

      if String.contains?(workload.name, ["/publish/", "/remove/"]) do
        assert activity.bus.reductions > 0
        assert activity.bus.after_gc_bytes > 0
      end
    end
  end

  test "candidate case IDs are unique across both sizes" do
    ids = Enum.map(Suite.workloads("candidates"), & &1.id)
    assert length(ids) == length(Enum.uniq(ids))
  end
end
