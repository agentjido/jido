Code.require_file("react_support.exs", __DIR__)

defmodule Jido.AI.Perf.ReActTest do
  use ExUnit.Case, async: false

  @moduletag :bench

  alias Jido.Test.Perf.AI.ReActSupport
  alias Jido.Test.Perf.Result

  test "sequential requests report retained state growth" do
    cases = ReActSupport.run(:state_growth, 3)
    assert Enum.map(cases, & &1.request) == [1, 2, 3]
    assert Enum.map(cases, & &1.model_calls) == [2, 2, 2]
    assert Enum.map(cases, & &1.tool_calls) == [1, 1, 1]
    assert Enum.map(cases, & &1.tool_rounds) == [1, 1, 1]
    assert cases |> Enum.map(& &1.thread_entries) |> strictly_increasing?()
    assert cases |> Enum.map(& &1.retained_external_bytes) |> strictly_increasing?()
  end

  test "fresh requests retain one stable workflow shape" do
    cases = ReActSupport.run(:fresh_workflow, 3)
    assert Enum.map(cases, & &1.request) == [1, 2, 3]
    assert cases |> Enum.map(& &1.workflow_components) |> Enum.uniq() |> length() == 1
    assert cases |> Enum.map(& &1.workflow_external_bytes) |> Enum.uniq() |> length() == 1
    assert cases |> Enum.map(& &1.thread_entries) |> Enum.uniq() |> length() == 1
    assert Enum.all?(cases, &(&1.compile_us >= 0 and &1.execution_us >= 0))
  end

  test "both manual runners write complete reports" do
    root = Path.expand("tmp/bench/ai/smoke")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    for {name, mode} <- [
          {"react_state_growth", "state_growth"},
          {"react_fresh_workflow", "fresh_workflow"}
        ] do
      reports =
        for repetition <- 1..2 do
          output = Path.join(root, "#{name}-#{repetition}.json")

          report =
            run_mix_report!(
              [
                "run",
                "--no-compile",
                "--no-deps-check",
                "test/perf/jido_ai/#{name}.exs",
                "--profile",
                "quick",
                "--output",
                output
              ],
              output
            )

          assert Result.validate(report) == []
          assert report["schema_version"] == 1
          assert report["mode"] == mode
          assert report["requests"] == 2
          assert report["provider"] == "deterministic-local"
          assert report["network"] == false
          assert length(report["cases"]) == 2
          assert Enum.all?(report["cases"], &(&1["model_calls"] == 2 and &1["tool_calls"] == 1))
          report
        end

      assert reports |> Enum.map(&Result.case_inventory/1) |> Enum.uniq() |> length() == 1
    end
  end

  test "the ReAct memory quick profile is repeatable and writes the common result" do
    root = Path.expand("tmp/bench/ai/memory-smoke")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    reports =
      for repetition <- 1..2 do
        output = Path.join(root, "react-memory-#{repetition}.json")

        report =
          run_mix_report!(
            ["run", "--no-compile", "--no-deps-check", "test/perf/jido_ai/react_memory.exs"],
            output,
            [
              {"JIDO_MEMORY_BENCH_PROFILE", "quick"},
              {"JIDO_MEMORY_BENCH_OUTPUT", "json"},
              {"JIDO_MEMORY_BENCH_FILE", output}
            ]
          )

        assert Result.validate(report) == []
        assert report["metadata"]["profile"] == "quick"
        assert length(report["cases"]) == 1
        report
      end

    assert reports |> Enum.map(&Result.case_inventory/1) |> Enum.uniq() |> length() == 1
  end

  defp run_mix_report!(arguments, output, extra_environment \\ []) do
    {log, status} =
      System.cmd(
        System.find_executable("mix"),
        arguments,
        env: [{"MIX_ENV", "test"} | extra_environment],
        stderr_to_stdout: true
      )

    assert status == 0, "benchmark failed:\n#{log}"
    assert File.regular?(output)
    output |> File.read!() |> JSON.decode!()
  end

  defp strictly_increasing?([first | rest]) do
    {_last, result} =
      Enum.reduce(rest, {first, true}, fn value, {previous, result} ->
        {value, result and value > previous}
      end)

    result
  end
end
