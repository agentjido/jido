Code.require_file("../support/script_runner.exs", __DIR__)
Code.require_file("../support/result.exs", __DIR__)

defmodule Jido.AI.Perf.ReActStressTest do
  use ExUnit.Case, async: false

  @moduletag :bench

  alias Jido.Test.Perf.{Result, ScriptRunner}

  test "the isolated ReAct runner writes a complete report" do
    output = Path.expand("tmp/bench/action_flow/smoke/react_stress.json")
    File.mkdir_p!(Path.dirname(output))
    report = ScriptRunner.run!("test/perf/jido_ai/react_stress.exs", output)

    assert Result.validate(report) == []
    assert report["settings"]["profile"] == "quick"
    assert Enum.all?(report["cases"], &(&1["validated_before_measurement"] == true))
  end
end
