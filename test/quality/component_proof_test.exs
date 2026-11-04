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
end
