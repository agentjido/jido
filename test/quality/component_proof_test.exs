Code.require_file("support/component_proof.exs", __DIR__)

defmodule Jido.Quality.ComponentProofTest do
  use ExUnit.Case, async: false

  alias Jido.Quality.ComponentProof

  @proof_path Path.join(__DIR__, "component_proof.yml")
  @root Path.expand("../..", __DIR__)

  test "the checked-in proof owns every production and public module" do
    proof = ComponentProof.load!(@proof_path)
    inventory = ComponentProof.module_inventory(@root)

    assert ComponentProof.validate(proof, @root) == []

    {owners, errors} = ComponentProof.ownership(proof, @root)

    assert errors == []
    assert map_size(owners) == 463
    assert Enum.all?(inventory.public_modules, &Map.has_key?(owners, &1))
  end

  test "rejects a new active component without a proof entry" do
    proof = ComponentProof.load!(@proof_path)
    active = component_ids(proof) ++ ["jido.new_component"]

    assert "active component is missing: jido.new_component" in ComponentProof.validate(proof, @root,
             active_components: active
           )
  end

  test "rejects a public module without a primary owner" do
    proof = ComponentProof.load!(@proof_path) |> with_inventory(["Other.Public"], ["Other.Public"])

    errors =
      ComponentProof.validate(proof, @root,
        active_components: component_ids(proof),
        inventory: %{production_modules: ["Other.Public"], public_modules: ["Other.Public"]},
        covenant_owners: %{}
      )

    assert "module Other.Public has no primary component owner" in errors
    assert "public module Other.Public has no primary component owner" in errors
  end

  test "rejects two primary owners for one public module" do
    proof = ComponentProof.load!(@proof_path) |> with_inventory(["Jido.Sample"], ["Jido.Sample"])
    components = component_ids(proof)

    errors =
      ComponentProof.validate(proof, @root,
        active_components: components,
        inventory: %{production_modules: ["Jido.Sample"], public_modules: ["Jido.Sample"]},
        covenant_owners: %{"Jido.Sample" => ["jido.agent", "jido.error"]}
      )

    assert "module Jido.Sample has two primary Covenant owners: jido.agent, jido.error" in errors
  end

  test "rejects a fuzz-required component profile without a fuzz group" do
    proof =
      @proof_path
      |> ComponentProof.load!()
      |> put_in(["proof_profiles", "expression_authoring", "fuzz", "evidence_group"], "missing")

    assert "profile expression_authoring proof fuzz has no evidence group" in ComponentProof.validate(proof, @root)
  end

  test "rejects missing load and benchmark evidence" do
    proof = ComponentProof.load!(@proof_path)

    invalid =
      proof
      |> put_in(["performance_profiles", "runtime_load", "load", "evidence_group"], "missing_load")
      |> put_in(
        [
          "performance_profiles",
          "react_benchmark",
          "benchmark",
          "evidence_group"
        ],
        "missing_benchmark"
      )

    errors = ComponentProof.validate(invalid, @root)
    assert "profile runtime_load proof load has no evidence group" in errors
    assert "profile react_benchmark proof benchmark has no evidence group" in errors
  end

  test "rejects a component without a known performance profile" do
    proof = ComponentProof.load!(@proof_path)
    [first | rest] = proof["components"]
    invalid = Map.put(proof, "components", [Map.put(first, "performance_profile", "missing") | rest])

    assert "component #{first["id"]} has unknown performance profile: \"missing\"" in ComponentProof.validate(
             invalid,
             @root
           )
  end

  test "load and benchmark catalogs cover exactly the required performance components" do
    proof = ComponentProof.load!(@proof_path)
    {:ok, load_catalog} = YamlElixir.read_from_file(Path.join(@root, "test/load/catalog.yml"))
    {:ok, benchmark_catalog} = YamlElixir.read_from_file(Path.join(@root, "test/bench/catalog.yml"))

    load_components = catalog_components(load_catalog)
    benchmark_components = catalog_components(benchmark_catalog)

    assert load_components == required_performance_components(proof, "load")
    assert benchmark_components == required_performance_components(proof, "benchmark")
  end

  test "rejects a not-applicable proof without an owner and specific reason" do
    proof = ComponentProof.load!(@proof_path)

    invalid =
      proof
      |> put_in(["proof_profiles", "closed_contract", "property", "owner"], "")
      |> put_in(["proof_profiles", "closed_contract", "property", "reason"], "short")

    errors = ComponentProof.validate(invalid, @root)
    assert "profile closed_contract proof property has no named owner" in errors
    assert "profile closed_contract proof property has no specific reason" in errors
  end

  test "rejects a supported authoring proof without an executable test" do
    proof =
      @proof_path
      |> ComponentProof.load!()
      |> put_in(["evidence_groups", "authoring"], ["test/quality/README.md"])

    assert "profile authoring_contract proof authoring has no executable test" in ComponentProof.validate(proof, @root)
  end

  defp with_inventory(proof, production, public) do
    Map.put(proof, "module_inventory", %{
      "production_count" => length(production),
      "production_sha256" => ComponentProof.digest(production),
      "public_count" => length(public),
      "public_sha256" => ComponentProof.digest(public)
    })
  end

  defp component_ids(proof), do: Enum.map(proof["components"], & &1["id"])

  defp catalog_components(catalog) do
    catalog["families"]
    |> Enum.flat_map(& &1["components"])
    |> MapSet.new()
  end

  defp required_performance_components(proof, type) do
    proof["components"]
    |> Enum.filter(fn component ->
      profile = proof["performance_profiles"][component["performance_profile"]]
      profile[type]["state"] == "required"
    end)
    |> Enum.map(& &1["id"])
    |> MapSet.new()
  end
end
