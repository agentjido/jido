defmodule Jido.Flow.GeneratedRegistryTest do
  use Covenant.Case, component: "jido_action.codec", async: true
  @moduletag obligation: "jido_action.codec.I6"

  alias Jido.Catalog
  alias Jido.Test.Flow.Codec, as: Codec
  alias Jido.Error.ValidationError
  alias Jido.Flow.Ref
  alias Jido.Test.Flow.Fixtures.FlowAuthoring
  alias Jido.Test.Flow.Fixtures.InlineParityFlow
  alias Jido.Test.Flow.Fixtures.NestedFlow
  alias Jido.Test.Action.Fixtures.Actions.{Add, Multiply}

  test "encode builds one deterministic temporary Catalog" do
    flow = FlowAuthoring.mixed_flow!()

    assert {:ok, document, %Catalog{} = registry} = Codec.encode(flow)
    assert {:ok, ^document, ^registry} = Codec.encode(flow)

    assert {:ok, Add} =
             Catalog.resolve(registry, {"actions/generated-1", 1})

    assert {:ok, Multiply} =
             Catalog.resolve(registry, {"actions/generated-2", 1})

    assert {:ok, NestedFlow} =
             Catalog.resolve(registry, {"flows/generated-1", 1})

    assert {:ok, generated_schema} =
             Catalog.resolve(registry, {"schemas/generated-1", 1})

    assert Jido.Joi.Schema.kind(generated_schema) == :map

    for {atom, index} <-
          Enum.with_index([:add, :amount, :count, :items, :kind, :owner, :value], 1) do
      assert {:ok, ^atom} =
               Catalog.resolve(registry, {"atoms/generated-#{index}", 1})
    end

    assert {:ok, ^flow} = Codec.decode(document, registry)
  end

  test "temporary IDs depend on the exact Flow" do
    flow = InlineParityFlow.flow()
    assert {:ok, document, registry} = Codec.encode(flow)

    action =
      flow.components
      |> Enum.map(fn {_name, %{call: instruction}} -> instruction.target end)
      |> Enum.max_by(&Atom.to_string/1)

    subset =
      Jido.Test.Flow.Builder.new!(%{
        name: "inline_registry_subset",
        components: [%{kind: :step, name: "only", action: action}],
        output: Ref.result("only")
      })

    assert {:ok, _subset_document, subset_registry} = Codec.encode(subset)
    assert {:ok, original_reference} = Catalog.reference(registry, action)
    assert {:ok, subset_reference} = Catalog.reference(subset_registry, action)
    refute original_reference == subset_reference

    assert {:error, %ValidationError{}} = Codec.decode(document, subset_registry)
  end

  test "generated Catalog leaves target contracts to Exec" do
    flow =
      Jido.Test.Flow.Builder.new!(%{
        name: "invalid_target",
        components: [%{kind: :step, name: "invalid", action: String}],
        output: Ref.result("invalid")
      })

    assert {:ok, _document, %Catalog{}} = Codec.encode(flow)
    assert {:error, %ValidationError{}} = Jido.Exec.compile(flow)
    assert {:error, %ValidationError{}} = Codec.encode(:invalid)
  end
end
