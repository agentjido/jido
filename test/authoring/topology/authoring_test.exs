Code.require_file("../support/topology/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.AuthoringTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec, Plan}
  alias JidoTest.Authoring.Topology.Corpus

  setup %{variant: variant} do
    Corpus.load!(variant)
    {:ok, spec: Corpus.spec(variant)}
  end

  for variant <- Corpus.variants(), form <- Corpus.forms() do
    @tag variant: variant, form: form
    test "#{variant}/#{form}: definition and saved JSON", %{spec: spec, form: form} do
      definition = Corpus.definition(spec, form)
      assert definition === Topology.new!(spec.attrs)
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

      for field <- ~w(id input plan state status extensions),
          do: refute(Map.has_key?(document, field))
    end

    @tag variant: variant, form: form
    test "#{variant}/#{form}: exact pure plans and invalid inputs", %{spec: spec, form: form} do
      definition = Corpus.definition(spec, form)

      for scenario <- spec.scenarios do
        assert {:ok, instance} =
                 Topology.instantiate(definition, id: "corpus", input: scenario.input)

        assert instance.definition === definition
        assert instance.input === scenario.normalized
        assert instance.plan === scenario.plan
        assert {:ok, plan} = Plan.build(definition, "corpus", scenario.normalized)
        assert plan === scenario.plan
      end

      for input <- spec.invalid_inputs do
        assert {:error, %Jido.Error.ValidationError{}} =
                 Topology.instantiate(definition, id: "corpus", input: input)
      end

      # A rejected input must not alter the definition used by later planning.
      scenario = hd(spec.scenarios)

      assert {:ok, recovered} =
               Topology.instantiate(definition, id: "corpus", input: scenario.input)

      assert recovered.plan === scenario.plan
    end
  end

  for variant <- Corpus.variants() do
    @tag variant: variant
    test "#{variant}: module, Builder, and Codec instance constructors", %{spec: spec} do
      for scenario <- spec.scenarios do
        opts = [id: "corpus", input: scenario.input]
        assert {:ok, from_module} = spec.module.new(opts)
        assert {:ok, from_builder} = Builder.build(Corpus.builder(spec), opts)
        assert {:ok, from_codec} = Codec.decode(spec.document, spec.registry, opts)
        assert from_module === from_builder
        assert from_codec === from_module
        assert from_module.plan === scenario.plan
      end
    end

    @tag variant: variant
    test "#{variant}: JSON rejects missing, mistyped, and untrusted fields", %{spec: spec} do
      for document <- [
            Map.delete(spec.document, "schema"),
            Map.put(spec.document, "version", 99),
            Map.put(spec.document, "schema", "untrusted/schema"),
            Map.put(spec.document, "schema", "agents/worker"),
            Map.put(spec.document, "plan", %{})
          ] do
        assert {:error, %Jido.Error.ValidationError{}} = Codec.decode(document, spec.registry)
      end
    end
  end
end
