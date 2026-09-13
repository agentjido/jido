Code.require_file("../support/topology/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.PluginBoundariesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Error.{ExecutionError, ValidationError}
  alias Jido.Topology
  alias Jido.Topology.{Builder, Codec, Plan}
  alias JidoTest.Authoring.Compiler
  alias JidoTest.Authoring.Topology.{Corpus, Fixtures}

  setup do
    Corpus.load_support!()
    Compiler.require_file!(Corpus.fixture("plugin_faults.exs"))
    :ok
  end

  for {module, error_type, message, code} <- [
        {Fixtures.FaultRaise, ExecutionError, "contribution failed", :plugin_callback_failed},
        {Fixtures.FaultThrow, ExecutionError, "contribution failed", :plugin_callback_failed},
        {Fixtures.FaultExit, ExecutionError, "contribution failed", :plugin_callback_failed},
        {Fixtures.FaultResult, ExecutionError, "invalid result", :plugin_invalid_callback_result},
        {Fixtures.FaultShape, ExecutionError, "invalid contribution",
         :plugin_invalid_callback_result},
        {Fixtures.FaultOwner, ExecutionError, "changed package identity",
         :plugin_invalid_callback_result},
        {Fixtures.FaultEntry, ValidationError, "Expected a map or keyword list", nil},
        {Fixtures.FaultConfig, ValidationError, "Topology owns Bus", nil},
        {Fixtures.FaultConflict, ValidationError, "Duplicate topology key", nil},
        {Fixtures.FaultEndpoint, ValidationError, "Unknown topology endpoint", nil},
        {Fixtures.FaultCycle, ValidationError, "contains a cycle", nil},
        {Fixtures.FaultDuplicateOwner, ValidationError, "only one owner", nil},
        {Fixtures.FaultRejected, ValidationError, "Plugin rejected authoring input", nil}
      ],
      form <- Corpus.forms() do
    @tag fixture_module: module, error_type: error_type, message: message, code: code, form: form
    test "#{inspect(module)}/#{form}: planning failure preserves the definition and JSON",
         context do
      spec = spec(context.fixture_module)
      definition = Corpus.definition(spec, context.form)
      assert definition === context.fixture_module.topology()
      assert Enum.map(definition.resources, & &1.key) == ["events"]
      assert definition.connections == []

      healthy = Corpus.definition(spec(Fixtures.FaultHealthy), :module)
      assert {:ok, before} = Topology.instantiate(healthy, id: "healthy")
      assert Map.keys(before.plan.resources) |> Enum.sort() == ["bus/events", "bus/inbox_healthy"]

      for result <- [
            Topology.instantiate(definition, id: "fault"),
            Plan.build(definition, "fault", %{}),
            context.fixture_module.new(id: "fault"),
            Builder.build(Builder.new(definition), id: "fault"),
            Codec.decode(spec.document, spec.registry, id: "fault")
          ] do
        assert_failure(result, context)
      end

      # The earlier Inbox contribution must not leak out of a failed expansion.
      assert {:ok, document} = Codec.encode(definition, spec.registry)
      assert document === spec.document
      assert {:ok, ^definition} = Codec.decode(document, spec.registry)
      assert context.fixture_module.topology() === definition
      assert_failure(Topology.instantiate(definition, id: "retry"), context)
      assert {:ok, after_failure} = Topology.instantiate(healthy, id: "healthy")
      assert after_failure === before
    end
  end

  test "group and included declarations retain Plugin error identity after JSON transport" do
    for attrs <- [
          %{groups: [%{key: :raise, module: Fixtures.FaultWorker, count: 0}]},
          %{includes: [%{key: :child, topology: Fixtures.FaultRaise}]}
        ] do
      definition = Topology.new!(Map.put(attrs, :name, "nested_fault"))
      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

      assert {:error, %ExecutionError{details: details}} =
               Codec.decode(document, registry, id: "fault")

      assert details.code == :plugin_callback_failed
      assert details.plugin == Fixtures.FaultPackage
      assert details.facet == Fixtures.FaultFacet
      assert details.callback == :contribute
      assert %ArgumentError{message: "authoring fault"} = details.error
      assert {:ok, ^document} = Codec.encode(definition, registry)
    end
  end

  defp spec(module) do
    definition = module.topology()
    {:ok, document, registry} = Codec.encode(definition)

    %{
      module: module,
      attrs: module.__topology_config__(),
      document: JSON.decode!(JSON.encode!(document)),
      registry: registry
    }
  end

  defp assert_failure(result, context) do
    assert {:error, error} = result
    assert is_struct(error, context.error_type)
    assert error.message =~ context.message

    if context.code do
      assert Jido.Error.code(error) == context.code
      assert error.details.plugin == Fixtures.FaultPackage
      assert error.details.facet == Fixtures.FaultFacet
    end

    case context.fixture_module do
      Fixtures.FaultRaise ->
        assert error.details.callback == :contribute
        assert %ArgumentError{message: "authoring fault"} = error.details.error

      Fixtures.FaultThrow ->
        assert Map.take(error.details, [:callback, :kind, :reason]) ==
                 %{callback: :contribute, kind: :throw, reason: :authoring_fault}

      Fixtures.FaultExit ->
        assert Map.take(error.details, [:callback, :kind, :reason]) ==
                 %{callback: :contribute, kind: :exit, reason: :authoring_fault}

      Fixtures.FaultOwner ->
        assert error.details.actual == Fixtures.InboxPackage

      Fixtures.FaultEndpoint ->
        assert error.details == %{path: [], key: "missing"}

      Fixtures.FaultRejected ->
        assert error.kind == :input
        assert error.details == %{reason: :authoring_fault}

      _ ->
        :ok
    end
  end
end
