Code.require_file("cases.exs", __DIR__)
Code.require_file("../compiler.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.Corpus do
  @moduledoc false
  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec}
  alias Jido.Codec.Registry
  alias JidoTest.Authoring.Compiler
  alias JidoTest.Authoring.Agents.{Cases, Fixtures}
  @fixtures Path.expand("fixtures", __DIR__)
  @variants [
    counter_keyword: {Fixtures.KeywordCounter, "counter"},
    counter_block: {Fixtures.BlockCounter, "counter"},
    inline: {Fixtures.InlineCounter, "inline"},
    flow_plugin: {Fixtures.FlowCounter, "flow_plugin"},
    required_profile: {Fixtures.RequiredProfile, "required_profile"},
    falsy_values: {Fixtures.FalsyValues, "falsy_values"},
    nested_profile: {Fixtures.NestedProfile, "nested_profile"},
    list_inputs: {Fixtures.ListInputs, "list_inputs"},
    bounded_value: {Fixtures.BoundedValue, "bounded_value"},
    static_metadata: {Fixtures.StaticMetadata, "static_metadata"},
    predicate_routes: {Fixtures.PredicateRoutes, "predicate_routes"},
    ordered_routes: {Fixtures.OrderedRoutes, "ordered_routes"},
    built_flow: {Fixtures.BuiltFlow, "built_flow"},
    ordered_plugins: {Fixtures.OrderedPlugins, "ordered_plugins"},
    extension_route: {Fixtures.ExtensionRoute, "extension_route"},
    custom_selection: {Fixtures.CustomSelection, "custom_selection"}
  ]

  def variants, do: Keyword.keys(@variants)
  def forms, do: [:module, :map, :keyword, :builder, :module_builder, :json]
  def fixture(relative), do: Path.join(@fixtures, relative)

  # Only selected tests load source. require_file/1 shares successful loads;
  # a failure belongs to the affected case, not a suite-wide setup_all.
  def load!(variant) do
    {_module, source} = Keyword.fetch!(@variants, variant)
    load_dependencies!()
    require_source!(source)
  end

  def load_dependencies!,
    do: Enum.each(["executables", "edge_support"], &require_source!/1)

  defp require_source!(file),
    do: Compiler.require_file!(fixture("#{file}.exs"))

  def compile_file(file), do: Compiler.compile_file(fixture(file))

  def spec(variant) do
    {module, _source} = Keyword.fetch!(@variants, variant)
    data = Cases.spec(variant, module)

    attrs =
      Map.merge(
        %{
          module: module,
          name: "authoring_#{data.id}",
          vsn: 1,
          description: nil,
          metadata: %{},
          plugins: [],
          routes: []
        },
        data.attrs
      )

    registry =
      data.references
      |> Map.merge(%{
        "agents/#{data.id}" => {:agent, module},
        "schemas/#{Map.get(data, :schema_id, data.id)}" => {:schema, attrs.schema}
      })
      |> Registry.new!()

    Map.merge(data, %{
      attrs: attrs,
      registry: registry,
      document: fixture("json/#{data.id}.json") |> File.read!() |> JSON.decode!(),
      initial_opts: Map.get(data, :initial_opts, []),
      source: "/authoring/#{data.id}"
    })
  end

  def builder(%{attrs: attrs}) do
    builder = Builder.new(Map.drop(attrs, [:routes, :plugins]))

    builder =
      Enum.reduce(attrs.plugins, builder, fn {module, opts}, acc ->
        Builder.plugin(acc, module, opts)
      end)

    Enum.reduce(attrs.routes, builder, fn {path, target, opts}, acc ->
      Builder.route(acc, path, target, opts)
    end)
  end

  def definition(spec, :module), do: spec.attrs.module.definition()
  def definition(spec, :map), do: Agent.new!(spec.attrs)
  def definition(spec, :keyword), do: Agent.new!(Map.to_list(spec.attrs))
  def definition(spec, :builder), do: Builder.build!(builder(spec))
  def definition(spec, :module_builder), do: Builder.build!(Builder.new(spec.attrs.module))

  def definition(spec, :json) do
    {:ok, definition} = Codec.decode(spec.document, spec.registry)
    definition
  end

  def instance(spec, definition, id),
    do: Agent.instantiate!(definition, Keyword.put(spec.initial_opts, :id, id))
end
