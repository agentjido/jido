Code.require_file("../compiler.exs", __DIR__)
Code.require_file("cases.exs", __DIR__)

defmodule JidoTest.Authoring.Topology.Corpus do
  @moduledoc false
  alias Jido.Topology
  alias Jido.Topology.Codec
  alias Jido.Codec.Registry
  alias JidoTest.Authoring.Compiler
  alias JidoTest.Authoring.Topology.{Cases, Fixtures}
  @fixtures Path.expand("fixtures", __DIR__)
  @variants [
    minimal: {Fixtures.Minimal, "minimal"},
    minimal_keyword: {Fixtures.KeywordMinimal, "minimal"},
    counted: {Fixtures.Counted, "counted"},
    keyed: {Fixtures.Keyed, "keyed"},
    ownership: {Fixtures.Ownership, "ownership"},
    bus: {Fixtures.Bus, "bus"},
    nested: {Fixtures.Nested, "nested"},
    repeated: {Fixtures.Repeated, "repeated"},
    deep: {Fixtures.Deep, "deep"},
    configured: {Fixtures.Configured, "configured"},
    plugin: {Fixtures.Plugin, "plugin"},
    combined: {Fixtures.Combined, "combined"}
  ]

  def variants, do: Keyword.keys(@variants)
  def forms, do: [:module, :map, :keyword, :json]
  def fixture(file), do: Path.join(@fixtures, file)
  def load_support!, do: Compiler.require_file!(fixture("support.exs"))

  def load!(variant) do
    load_support!()
    {_module, source} = Keyword.fetch!(@variants, variant)
    Compiler.require_file!(fixture(source <> ".exs"))
  end

  def spec(variant) do
    {module, _source} = Keyword.fetch!(@variants, variant)
    data = Cases.spec(variant)

    attrs =
      Map.merge(
        %{
          name: "authoring_" <> data.id,
          schema: Zoi.object(%{}),
          metadata: %{},
          agents: [],
          groups: [],
          resources: [],
          relationships: [],
          connections: [],
          includes: [],
          imports: [],
          exports: [],
          startup: %{}
        },
        data.attrs
      )

    registry =
      Registry.new!(
        Map.merge(
          %{
            "agents/worker" => {:agent, Fixtures.Worker},
            "agents/plugin_worker" => {:agent, Fixtures.PluginWorker},
            ("schemas/" <> data.id) => {:schema, attrs.schema},
            "schemas/child" => {:schema, Zoi.object(%{label: Zoi.string()})}
          },
          Map.new(
            [:label, :value, :count, :index, :members, :key, :role_count],
            &{"atoms/#{&1}", {:atom, &1}}
          )
        )
        |> Map.merge(Map.get(data, :references, %{}))
      )

    Map.merge(data, %{
      attrs: attrs,
      module: module,
      registry: registry,
      document: fixture("json/" <> data.id <> ".json") |> File.read!() |> JSON.decode!(),
      invalid_inputs: Map.get(data, :invalid_inputs, [])
    })
  end

  def definition(spec, :module), do: spec.module.topology()
  def definition(spec, :map), do: Topology.new!(spec.attrs)
  def definition(spec, :keyword), do: Topology.new!(Map.to_list(spec.attrs))

  def definition(spec, :json) do
    {:ok, definition} = Codec.decode(spec.document, spec.registry)
    definition
  end
end
