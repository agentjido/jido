defmodule JidoTest.Load.CatalogTest do
  use ExUnit.Case, async: true

  @moduletag :load
  @root Path.expand("../..", __DIR__)

  test "each load family has an owned bounded workload and executable evidence" do
    {:ok, catalog} = YamlElixir.read_from_file(Path.join(__DIR__, "catalog.yml"))
    assert catalog["schema_version"] == 1
    assert catalog["families"] != []

    ids = Enum.map(catalog["families"], & &1["id"])
    assert length(ids) == length(Enum.uniq(ids))

    for family <- catalog["families"] do
      for field <- ~w(id components owner command workload limiter bounded_case evidence) do
        assert present?(family[field]), "load family #{family["id"] || "unknown"} is missing #{field}"
      end

      evidence = Path.join(@root, family["evidence"])
      assert File.regular?(evidence)
      assert String.ends_with?(evidence, "_test.exs")
      assert family["command"] =~ "mix test.load"
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(_value), do: false
end
