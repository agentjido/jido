Code.require_file("../support/script_runner.exs", __DIR__)
Code.require_file("../support/result.exs", __DIR__)

defmodule Jido.Flow.Perf.RunnerTest do
  use ExUnit.Case, async: false

  @moduletag :bench
  @runners %{
    "dsl_compile" => "test/perf/jido_flow/dsl_compile.exs",
    "flow_compile" => "test/perf/jido_flow/flow_compile.exs"
  }

  alias Jido.Test.Perf.{Result, ScriptRunner}

  test "each Flow runner validates its work and writes one complete report" do
    root = Path.expand("tmp/perf/smoke")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    for {runner, script} <- @runners do
      reports =
        for repetition <- 1..2 do
          output = Path.join(root, "#{runner}-#{repetition}.json")
          report = ScriptRunner.run!(script, output)
          assert_complete(report)
          report
        end

      assert reports |> Enum.map(&Result.case_inventory/1) |> Enum.uniq() |> length() == 1
    end
  end

  test "Flow runners reject result files outside the ignored report tree" do
    {log, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-compile",
          "--no-deps-check",
          "test/perf/jido_flow/flow_compile.exs",
          "--output",
          "flow-compile.json"
        ],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert log =~ "benchmark output must be under tmp/perf"
    refute File.exists?("flow-compile.json")
  end

  defp assert_complete(report) do
    assert Result.validate(report) == []
    assert report["schema_version"] == 1
    assert report["settings"]["profile"] == "quick"
    assert report["cases"] != []
    assert Enum.all?(report["cases"], &(&1["validated_before_measurement"] == true))
    refute Map.has_key?(report, "thresholds")
  end
end
