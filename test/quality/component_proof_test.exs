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
    assert map_size(owners) == 464
    assert Enum.all?(inventory.public_modules, &Map.has_key?(owners, &1))
  end

  test "rejects a new active component without a proof entry" do
    proof = ComponentProof.load!(@proof_path)
    active = component_ids(proof) ++ ["jido.new_component"]

    assert "active component is missing: jido.new_component" in ComponentProof.validate(proof, @root,
             active_components: active
           )
  end

  test "each active component has one registered canonical behavior owner" do
    proof = ComponentProof.load!(@proof_path)
    components = component_ids(proof)
    behavior_claims = Enum.filter(proof["claims"], &String.ends_with?(&1["id"], ".behavior"))
    claim_components = Enum.map(behavior_claims, & &1["component"])

    assert Enum.sort(claim_components) == Enum.sort(components)
    assert Enum.all?(behavior_claims, &is_binary(get_in(&1, ["canonical", "owner"])))
    assert Enum.all?(behavior_claims, &(&1["covenant_obligations"] == "all"))
  end

  test "each example owns one documentation claim and supplements its component behavior" do
    proof = ComponentProof.load!(@proof_path)
    {:ok, catalog} = YamlElixir.read_from_file(Path.join(@root, "test/examples/catalog.yml"))

    example_claims =
      proof["claims"]
      |> Enum.filter(&String.starts_with?(&1["id"], "example."))
      |> Map.new(&{&1["id"], &1})

    assert map_size(example_claims) == length(catalog["examples"])

    Enum.each(catalog["examples"], fn example ->
      claim = Map.fetch!(example_claims, "example.#{example["id"]}.documentation")

      assert claim["component"] == example["component"]
      assert claim["canonical"]["mode"] == "example"
      assert claim["canonical"]["evidence_group"] == "examples"
      assert claim["canonical"]["owner"] == example["test"]
    end)

    example_components = catalog["examples"] |> Enum.map(& &1["component"]) |> Enum.uniq()
    components = Map.new(proof["components"], &{&1["id"], &1})
    behavior_claims = Map.new(proof["claims"], &{&1["id"], &1})

    Enum.each(example_components, fn component ->
      profile = proof["proof_profiles"][components[component]["proof_profile"]]
      behavior = behavior_claims["#{component}.behavior"]

      assert profile["example"] == %{"state" => "required", "evidence_group" => "examples"}

      assert Enum.any?(behavior["supplemental"], fn supplement ->
               supplement["mode"] == "example" and supplement["evidence_group"] == "examples"
             end)
    end)
  end

  test "rejects two canonical owners for one claim" do
    proof = ComponentProof.load!(@proof_path)
    [first | _rest] = proof["claims"]
    invalid = Map.update!(proof, "claims", &[first | &1])

    assert "claim has two canonical owners: #{inspect(first["id"])}" in ComponentProof.validate(invalid, @root)
  end

  test "rejects a canonical owner without its component Covenant case" do
    proof = ComponentProof.load!(@proof_path)
    invalid = put_in(proof, ["claims", Access.at(0), "canonical", "owner"], "test/jido/public_api_test.exs")
    [first | _rest] = proof["claims"]

    assert "claim #{inspect(first["id"])} canonical owner has no #{first["component"]} Covenant case" in ComponentProof.validate(
             invalid,
             @root
           )
  end

  test "accepts a non-Covenant claim with an executable canonical owner" do
    proof = ComponentProof.load!(@proof_path)

    claim = %{
      "id" => "jido.agent.synthetic_authoring_contract",
      "component" => "jido.agent",
      "canonical" => %{
        "mode" => "authoring",
        "evidence_group" => "authoring",
        "owner" => "test/authoring/agent_equivalence_test.exs",
        "proves" => "Executable Agent authoring tests own this distinct synthetic DSL claim."
      }
    }

    valid = Map.update!(proof, "claims", &[claim | &1])
    assert ComponentProof.validate(valid, @root) == []
  end

  test "rejects canonical evidence repeated as supplemental evidence" do
    proof = ComponentProof.load!(@proof_path)
    [first | _rest] = proof["claims"]

    repeated = %{
      "mode" => first["canonical"]["mode"],
      "evidence_group" => first["canonical"]["evidence_group"],
      "proves" => "This text is long enough but repeats the canonical proof without distinct value."
    }

    invalid = put_in(proof, ["claims", Access.at(0), "supplemental"], [repeated])

    assert "claim #{inspect(first["id"])} repeats its canonical proof as supplemental evidence" in ComponentProof.validate(
             invalid,
             @root
           )
  end

  test "rejects an evidence group without a proof owner" do
    proof = ComponentProof.load!(@proof_path)
    invalid = put_in(proof, ["evidence_groups", "orphan"], ["test/jido"])

    assert "evidence group has no proof owner: orphan" in ComponentProof.validate(invalid, @root)
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
    {:ok, catalog} = YamlElixir.read_from_file(Path.join(@root, "test/perf/catalog.yml"))

    load_components = catalog_components(catalog, "load")
    benchmark_components = catalog_components(catalog, "benchmark")

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

  defp catalog_components(catalog, mode) do
    catalog["families"]
    |> Enum.filter(&(&1["mode"] == mode))
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
