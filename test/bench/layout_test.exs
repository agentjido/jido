defmodule JidoTest.Bench.LayoutTest do
  use ExUnit.Case, async: true

  @moduletag :bench
  @root Path.expand("../..", __DIR__)

  test "test bench is the only benchmark source tree" do
    refute File.exists?(Path.join(@root, "bench"))

    local_files = [
      ".formatter.exs",
      ".github/workflows/ci.yml",
      "AGENTS.md",
      "README.md",
      "mix.exs"
    ]

    local_files =
      (local_files ++
         Path.wildcard(Path.join(@root, "test/bench/**/*")))
      |> Enum.filter(&File.regular?/1)

    for file <- local_files do
      text = file |> absolute_path() |> File.read!()
      refute text =~ ~r/\bmix run bench\//, "top-level benchmark command remains in #{file}"
      refute text =~ ~r/\]\(bench\//, "top-level benchmark link remains in #{file}"
      refute text =~ ~r/`bench\//, "top-level benchmark path remains in #{file}"
    end
  end

  test "ported manifest targets stay under test bench" do
    {:ok, manifest} = YamlElixir.read_from_file(Path.join(@root, "test/quality/source_manifest.yml"))

    benchmark_targets =
      manifest["assets"]
      |> Enum.filter(&(&1["disposition"] == "ported" and &1["quality_surface"] in ["benchmark", "benchmark_smoke"]))
      |> Enum.map(& &1["target_path"])

    assert benchmark_targets != []
    assert Enum.all?(benchmark_targets, &String.starts_with?(&1, "test/bench/"))
  end

  defp absolute_path(path) do
    if Path.type(path) == :absolute, do: path, else: Path.join(@root, path)
  end
end
