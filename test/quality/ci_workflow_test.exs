defmodule Jido.Quality.CIWorkflowTest do
  use ExUnit.Case, async: true

  @workflow_path Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @required_jobs [
    "Format",
    "Compile warnings",
    "Unit",
    "Covenant",
    "Reach architecture",
    "Authoring",
    "Examples",
    "Bounded properties",
    "Bounded fuzz",
    "Local system",
    "Load",
    "Peer",
    "Benchmark smoke"
  ]

  test "every required offline surface has a named job" do
    entries = get_in(workflow(), ["jobs", "required", "strategy", "matrix", "include"])
    names = Enum.map(entries, & &1["name"])
    commands = Map.new(entries, &{&1["name"], &1["command"]})

    assert @required_jobs -- names == []
    assert commands["Unit"] =~ "mix test"
    assert commands["Covenant"] == "mix test.contracts"
    assert commands["Reach architecture"] == "mix reach.check --arch --smells"
    assert commands["Authoring"] =~ "mix test.authoring"
    assert commands["Examples"] =~ "mix test.examples"
    assert commands["Bounded properties"] =~ "mix test.property"
    assert commands["Bounded fuzz"] =~ "mix test.fuzz"
    assert commands["Local system"] =~ "mix test.system"
    assert commands["Load"] =~ "mix test.load"
    assert commands["Peer"] =~ "mix test.peer"
    assert commands["Benchmark smoke"] =~ "mix test.bench"
    refute Enum.any?(entries, &String.contains?(&1["command"], "test.live"))
    refute Enum.any?(entries, &String.contains?(&1["command"], "test.services"))
  end

  test "extended, service, and live jobs have explicit trigger boundaries" do
    jobs = workflow()["jobs"]

    assert jobs["extended"]["if"] =~ "schedule"
    assert jobs["extended"]["if"] =~ "run_extended"
    assert jobs["services"]["if"] =~ "workflow_dispatch"
    assert jobs["services"]["if"] =~ "run_services"
    assert jobs["live"]["if"] =~ "workflow_dispatch"
    assert jobs["live"]["if"] =~ "run_live"

    extended_entries = jobs["extended"]["strategy"]["matrix"]["include"]
    extended_names = Enum.map(extended_entries, & &1["name"])
    extended_commands = Map.new(extended_entries, &{&1["name"], &1["command"]})

    assert extended_names == ["Extended fuzz", "Load burn-in", "Extended benchmarks"]
    assert extended_commands["Load burn-in"] =~ "test/perf/jido_exec/burn_in.sh"
    assert extended_commands["Extended benchmarks"] =~ "test/perf/jido_flow/flow_compile.exs"
    assert extended_commands["Extended benchmarks"] =~ "test/perf/jido_exec/flow_run.exs"
    assert extended_commands["Extended benchmarks"] =~ "test/perf/jido_ai/react_stress.exs"
  end

  test "the objective quality job runs coverage and report gates and uploads evidence" do
    steps = get_in(workflow(), ["jobs", "objective-quality", "steps"])
    commands = steps |> Enum.map(& &1["run"]) |> Enum.reject(&is_nil/1)
    upload = Enum.find(steps, &(&1["uses"] == "actions/upload-artifact@v4"))

    assert "mix quality.coverage" in commands
    assert "mix quality.report" in commands
    assert upload["if"] == "always()"
    assert upload["with"]["path"] == "tmp/quality"
  end

  defp workflow do
    case YamlElixir.read_from_file(@workflow_path) do
      {:ok, workflow} -> workflow
      {:error, error} -> raise "cannot read CI workflow: #{inspect(error)}"
    end
  end
end
