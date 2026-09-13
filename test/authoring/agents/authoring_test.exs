Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.AuthoringTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec}
  alias JidoTest.Authoring.Agents.Corpus

  setup %{variant: variant} do
    Corpus.load!(variant)
    {:ok, spec: Corpus.spec(variant)}
  end

  for variant <- Corpus.variants(), form <- Corpus.forms() do
    @tag variant: variant, form: form
    test "#{variant}/#{form}: definition, JSON, and instance contract", %{spec: spec, form: form} do
      definition = Corpus.definition(spec, form)
      assert definition === Agent.new!(spec.attrs)
      assert Agent.definition?(definition)
      assert definition.id == nil
      assert definition.state == nil
      assert {:ok, document} = Codec.encode(definition, spec.registry)
      assert document === spec.document

      Enum.reduce(1..3, definition, fn _, current ->
        assert {:ok, ^document} = Codec.encode(current, spec.registry)
        assert {:ok, decoded} = Codec.decode(JSON.decode!(JSON.encode!(document)), spec.registry)
        assert decoded === definition
        decoded
      end)

      assert {:ok, generated, registry} = Codec.encode(definition)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(generated)), registry)

      for field <- ~w(id state interfaces signal_source inline_action) do
        refute Map.has_key?(document, field)
      end

      instance = Corpus.instance(spec, definition, "default")
      assert instance.state === spec.initial
      assert Agent.definition(instance) === definition
      assert {:ok, ^document} = Codec.encode(instance, spec.registry)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.instantiate(definition, state: spec.invalid_state)

      overridden = Agent.instantiate!(definition, id: "override", state: spec.override)
      assert overridden.state === spec.override_state
      assert overridden.id == "override"
    end
  end

  for variant <- Corpus.variants() do
    @tag variant: variant
    test "#{variant}: module accessors and instance constructors", %{spec: spec} do
      module = spec.attrs.module
      expected = Agent.new!(spec.attrs)
      assert module.schema() === spec.attrs.schema
      assert module.metadata() === spec.attrs.metadata
      assert module.vsn() === spec.attrs.vsn
      assert module.routes() === expected.routes
      assert module.plugins() === expected.plugins

      opts = [id: "override", state: spec.override]
      assert {:ok, decoded} = Codec.decode(spec.document, spec.registry, opts)

      for instance <- [
            module.new!(opts),
            Agent.instantiate!(module, opts),
            Builder.build!(Corpus.builder(spec), opts),
            decoded
          ] do
        assert instance.state === spec.override_state
        assert instance.id == "override"
        assert Agent.instance?(instance)
      end
    end
  end
end
