Code.require_file("authoring_equivalence.ex", __DIR__)

defmodule Jido.Examples.Compilation.AuthoringEquivalenceTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "DSL, data, and JSON produce equal values and identities" do
    module = Jido.Examples.Compilation.AuthoringEquivalence
    dsl = apply(module, :flow, [])
    data = apply(module, :from_map, [])
    assert {:ok, json} = apply(module, :from_json, [])
    assert dsl == data
    assert json == data
    assert Jido.Flow.semantic_identity(dsl) == Jido.Flow.semantic_identity(data)
    assert Jido.Flow.semantic_identity(json) == Jido.Flow.semantic_identity(data)
  end
end
