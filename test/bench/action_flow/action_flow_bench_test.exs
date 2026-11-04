Code.require_file("../support/result.exs", __DIR__)

defmodule JidoTest.Bench.ActionFlowBenchTest do
  use ExUnit.Case, async: false

  @moduletag :bench
  @runners ~w(flow_compile flow_run dsl_compile react_stress)

  alias Jido.Bench.Result

  test "each quick runner validates its work and writes one complete report" do
    root = Path.expand("tmp/bench/action_flow/smoke")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    for runner <- @runners do
      reports =
        for repetition <- 1..2 do
          output = Path.join(root, "#{runner}-#{repetition}.json")
          report = run_report!(runner, output)

          assert Result.validate(report) == []
          assert report["schema_version"] == 1
          assert report["settings"]["profile"] == "quick"
          assert is_binary(report["source"]["commit"])
          assert is_binary(report["source"]["sha256"])
          assert report["source"]["files"] > 0
          assert is_binary(report["environment"]["elixir"])
          assert is_binary(report["environment"]["otp"])
          assert report["cases"] != []
          assert Enum.all?(report["cases"], &(&1["validated_before_measurement"] == true))
          refute Map.has_key?(report, "thresholds")
          report
        end

      assert reports |> Enum.map(&Result.case_inventory/1) |> Enum.uniq() |> length() == 1
    end

    assert root |> Path.join("*.json") |> Path.wildcard() |> length() == length(@runners) * 2
  end

  test "runners reject result files outside the ignored report tree" do
    {log, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-compile",
          "--no-deps-check",
          "test/bench/action_flow/flow_compile.exs",
          "--output",
          "flow-compile.json"
        ],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert log =~ "benchmark output must be under tmp/bench/action_flow"
    refute File.exists?("flow-compile.json")
  end

  defp run_report!(runner, output) do
    {log, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-compile",
          "--no-deps-check",
          "test/bench/action_flow/#{runner}.exs",
          "--profile",
          "quick",
          "--output",
          output
        ],
        env: [
          {"MIX_ENV", "test"},
          {"ERL_FLAGS", "+S 4:4 +SDcpu 2 +SDio 1"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, "#{runner} failed:\n#{log}"
    assert File.regular?(output)
    output |> File.read!() |> JSON.decode!()
  end
end
