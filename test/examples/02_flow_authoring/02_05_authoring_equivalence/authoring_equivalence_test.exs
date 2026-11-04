Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Compilation.AuthoringEquivalenceTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("02_flow_authoring/02_05_authoring_equivalence/authoring_equivalence.ex")

    :ok
  end

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
