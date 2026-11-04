Code.require_file("../../../bench/ai/react_support.exs", __DIR__)

defmodule JidoTest.Bench.AI.ReActBenchTest do
  use ExUnit.Case, async: false

  @moduletag :bench

  alias Jido.Bench.AI.ReActSupport

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
      output = Path.join(root, "#{name}.json")

      {log, status} =
        System.cmd(
          System.find_executable("mix"),
          [
            "run",
            "--no-compile",
            "--no-deps-check",
            "bench/ai/#{name}.exs",
            "--requests",
            "2",
            "--output",
            output
          ],
          env: [{"MIX_ENV", "test"}],
          stderr_to_stdout: true
        )

      assert status == 0, "#{name} failed:\n#{log}"
      report = output |> File.read!() |> JSON.decode!()
      assert report["schema_version"] == 1
      assert report["mode"] == mode
      assert report["requests"] == 2
      assert report["provider"] == "deterministic-local"
      assert report["network"] == false
      assert length(report["cases"]) == 2
      assert Enum.all?(report["cases"], &(&1["model_calls"] == 2 and &1["tool_calls"] == 1))
    end
  end

  defp strictly_increasing?([first | rest]) do
    {_last, result} =
      Enum.reduce(rest, {first, true}, fn value, {previous, result} ->
        {value, result and value > previous}
      end)

    result
  end
end
