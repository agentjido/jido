Code.require_file("../support/script_runner.exs", __DIR__)
Code.require_file("../support/result.exs", __DIR__)

defmodule Jido.Exec.Perf.RunnerTest do
  use ExUnit.Case, async: false

  @moduletag :bench

  alias Jido.Test.Perf.{Result, ScriptRunner}

  test "the execution runner validates its work and writes a complete report" do
    root = Path.expand("tmp/bench/action_flow/smoke")
    File.mkdir_p!(root)

    reports =
      for repetition <- 1..2 do
        output = Path.join(root, "flow_run-#{repetition}.json")
        report = ScriptRunner.run!("test/perf/jido_exec/flow_run.exs", output)
        assert Result.validate(report) == []
        assert report["settings"]["profile"] == "quick"
        assert Enum.all?(report["cases"], &(&1["validated_before_measurement"] == true))
        report
      end

    assert reports |> Enum.map(&Result.case_inventory/1) |> Enum.uniq() |> length() == 1
  end
end
