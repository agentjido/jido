Code.require_file("support/catalog.exs", __DIR__)

defmodule Jido.Perf.CatalogTest do
  use ExUnit.Case, async: true

  @moduletag :load
  @moduletag :bench
  @root Path.expand("../..", __DIR__)

  alias Jido.Test.Perf.Catalog

  test "the catalog is complete and its commands and evidence are current" do
    catalog = Catalog.load!()
    assert Catalog.validate(catalog) == []

    {:ok, proof_map} =
      YamlElixir.read_from_file(Path.expand("../quality/component_proof.yml", __DIR__))

    components = MapSet.new(proof_map["components"], & &1["id"])

    readme = File.read!(Path.join(__DIR__, "README.md"))

    for family <- catalog["families"] do
      assert readme =~ family["command"], "missing quick command for #{family["id"]}"
      assert family["component"] in components
      assert family["component"] in family["components"]
      assert Enum.all?(family["components"], &(&1 in components))
      assert File.regular?(Path.join(@root, family["evidence"]))

      if family["mode"] == "benchmark" do
        assert family["quick_profile"] in family["supported_profiles"]

        for profile <- family["supported_profiles"] do
          settings = family["profiles"][profile]
          assert settings["warmup"] in 0..5
          assert settings["sample_count"] in 1..100
        end
      else
        assert family["mode"] == "load"
        assert family["command"] =~ "mix test.load"
      end
    end
  end

  test "the catalog has no portable timing threshold" do
    keys = deep_keys(Catalog.load!())
    refute Enum.any?(keys, &String.contains?(&1, "threshold"))
    refute Enum.any?(keys, &String.contains?(&1, "maximum_ms"))
  end

  test "invalid catalog data is rejected" do
    catalog = Catalog.load!()
    [first | rest] = catalog["families"]

    invalid =
      catalog
      |> Map.put("schema_version", 2)
      |> Map.put("families", [Map.delete(first, "limiter"), Map.delete(first, "limiter") | rest])

    errors = Catalog.validate(invalid)
    assert "catalog schema_version must equal 1" in errors
    assert "duplicate perf family: #{inspect(first["id"])}" in errors
    assert "perf family #{first["id"]} is missing limiter" in errors
  end

  defp deep_keys(value) when is_map(value) do
    Enum.flat_map(value, fn {key, child} -> [to_string(key) | deep_keys(child)] end)
  end

  defp deep_keys(value) when is_list(value), do: Enum.flat_map(value, &deep_keys/1)
  defp deep_keys(_value), do: []
end
