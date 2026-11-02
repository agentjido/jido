defmodule Jido.Flow.GeneratedRegistryTest do
  use Covenant.Case, component: "jido_action.codec", async: true
  @moduletag obligation: "jido_action.codec.I6"

  alias Jido.Authoring.Registry
  alias Jido.Flow.Codec
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.FlowAuthoring
  alias JidoActionTest.Fixtures.InlineParityFlow
  alias JidoActionTest.Fixtures.NestedFlow
  alias JidoActionTest.Fixtures.Actions.{Add, Multiply}

  test "encode builds one deterministic temporary Authoring Registry" do
    flow = FlowAuthoring.mixed_flow!()

    assert {:ok, document, %Registry{} = registry} = Codec.encode(flow)
    assert {:ok, ^document, ^registry} = Codec.encode(flow)

    assert {:ok, Add} =
             Registry.resolve(registry, {"actions/generated-1", 1}, :action)

    assert {:ok, Multiply} =
             Registry.resolve(registry, {"actions/generated-2", 1}, :action)

    assert {:ok, NestedFlow} =
             Registry.resolve(registry, {"flows/generated-1", 1}, :flow)

    assert {:ok, %Zoi.Types.Map{}} =
             Registry.resolve(registry, {"schemas/generated-1", 1}, :schema)

    for {atom, index} <-
          Enum.with_index([:add, :amount, :count, :items, :kind, :owner, :value], 1) do
      assert {:ok, ^atom} =
               Registry.resolve(
                 registry,
                 {"atoms/generated-#{index}", 1},
                 :atom
               )
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
      JidoActionTest.FlowBuilder.new!(%{
        name: "inline_registry_subset",
        components: [%{kind: :step, name: "only", action: action}],
        output: Ref.result("only")
      })

    assert {:ok, _subset_document, subset_registry} = Codec.encode(subset)
    assert {:ok, original_reference} = Registry.reference(registry, :action, action)
    assert {:ok, subset_reference} = Registry.reference(subset_registry, :action, action)
    refute original_reference == subset_reference

    assert {:error, %InvalidDefinitionError{}} = Codec.decode(document, subset_registry)
  end

  test "generated Registry leaves target contracts to Exec" do
    flow =
      JidoActionTest.FlowBuilder.new!(%{
        name: "invalid_target",
        components: [%{kind: :step, name: "invalid", action: String}],
        output: Ref.result("invalid")
      })

    assert {:ok, _document, %Registry{}} = Codec.encode(flow)
    assert {:error, %InvalidDefinitionError{}} = Jido.Exec.compile(flow)
    assert {:error, %InvalidDefinitionError{}} = Codec.encode(:invalid)
  end
end
