defmodule Jido.Agent.DSL.Topology.Entry do
  @moduledoc false

  alias Jido.Agent.{Authoring, Topology}

  fields =
    for kind <- [:binding | Enum.map(Topology.collections(), &elem(&1, 0))],
        {field, _options} <- Topology.schema(kind),
        do: field

  defstruct [:__kind__, :__spark_metadata__ | Enum.uniq(fields)]

  def entity(kind, name, args, drop \\ []) do
    fields =
      Topology.schema(kind)
      |> Keyword.drop(drop)
      |> Authoring.dsl_schema()

    %Spark.Dsl.Entity{
      name: name,
      target: Jido.Agent.DSL.Topology.Entry,
      args: args,
      auto_set_fields: [__kind__: kind],
      schema: fields
    }
  end
end

defmodule Jido.Agent.DSL.Topology.Extension do
  @moduledoc false

  alias Jido.Agent.DSL.Topology.Entry
  alias Jido.Agent.Topology

  @binding Entry.entity(:binding, :bind, [:key])
  @include %{
    Entry.entity(:include, :include, [:key, :topology], [:bindings])
    | entities: [bindings: [@binding]]
  }
  @exports Enum.map([:agent, :group, :bus], fn kind ->
             spec = Entry.entity(:export, kind, [:key], [:kind])
             %{spec | auto_set_fields: spec.auto_set_fields ++ [kind: kind]}
           end)
  @imports Enum.map([:agent, :bus], fn kind ->
             spec = Entry.entity(:import, kind, [:key], [:kind])
             %{spec | auto_set_fields: spec.auto_set_fields ++ [kind: kind]}
           end)
  @bus %{
    Entry.entity(:resource, :bus, [:key], [:kind])
    | auto_set_fields: [__kind__: :resource, kind: :bus]
  }

  @sections Enum.map(
              [
                agents: [
                  Entry.entity(:agent, :agent, [:key, {:optional, :module, nil}]),
                  Entry.entity(:group, :group, [:key, {:optional, :module, nil}])
                ],
                resources: [@bus],
                relationships: [Entry.entity(:owns, :owns, [:parent, :child])],
                connections: [Entry.entity(:subscribe, :subscribe, [:agent])],
                topologies: [@include],
                imports: @imports,
                exports: @exports
              ],
              fn {name, entities} ->
                %Spark.Dsl.Section{name: name, patchable?: true, entities: entities}
              end
            )

  def mark_block do
    quote generated: true do
      Module.put_attribute(__MODULE__, :jido_agent_topology_declared, true)
    end
  end

  use Spark.Dsl.Extension,
    sections: [
      %Spark.Dsl.Section{
        name: :topology,
        patchable?: true,
        after_define: {__MODULE__, :mark_block},
        imports: [Jido.Agent.Topology.Reference, Jido.Agent.Topology.Ref],
        schema: [
          schema: [type: {:custom, Jido.Agent.Authoring.Compiler, :validate_schema_storage, []}],
          metadata: [type: :map],
          children: [type: {:list, :map}]
        ],
        sections:
          @sections ++
            [
              %Spark.Dsl.Section{
                name: :startup,
                patchable?: true,
                schema: Topology.schema(:startup)
              }
            ]
      }
    ]
end

defmodule Jido.Agent.DSL.Topology do
  @moduledoc false

  alias Jido.Agent.Authoring
  alias Jido.Agent.Authoring.{Compiler, SourceMap}
  alias Jido.Agent.Authoring.Extension, as: AuthoringExtension
  alias Jido.Agent.DSL.Topology.Entry
  alias Jido.Agent.Topology
  alias Spark.Dsl.Extension

  def lower(extensions, dsl, env) do
    if Module.get_attribute(env.module, :jido_agent_topology_declared) == true or extensions != [] do
      config = options(dsl, [:topology], [:schema, :metadata, :children])

      {entries, foreign} =
        dsl
        |> Enum.filter(fn {path, value} -> is_list(path) and is_map(value) end)
        |> Enum.reject(fn {path, _value} -> List.first(path) in [:agent, :routes, :schedules] end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.flat_map(fn {path, _value} -> Extension.get_entities(dsl, path) end)
        |> Enum.split_with(&is_struct(&1, Entry))

      grouped = Enum.group_by(entries, &Keyword.fetch!(Topology.collections(), &1.__kind__))

      fields =
        Map.new(grouped, fn {field, entries} -> {field, Enum.map(entries, &lower_entry/1)} end)

      config = Map.merge(config, fields)

      startup =
        options(dsl, [:topology, :startup], Keyword.keys(Topology.schema(:startup)))

      config = if startup == %{}, do: config, else: Map.put(config, :startup, startup)

      sources =
        SourceMap.section(dsl, [:topology], [:schema, :metadata, :children], [:topology])
        |> Map.merge(
          SourceMap.section(dsl, [:topology, :startup], Keyword.keys(Topology.schema(:startup)), [
            :topology,
            :startup
          ])
        )

      sources = SourceMap.collect(grouped, sources, &entry_sources/2)

      config =
        AuthoringExtension.lower(extensions, config, foreign, :topology)
        |> Authoring.at(:topology)
        |> Compiler.unwrap!(env, sources)

      {config, sources}
    else
      {nil, %{}}
    end
  end

  defp options(dsl, path, fields) do
    for field <- fields,
        {:ok, value} <- [Extension.fetch_opt(dsl, path, field)],
        into: %{},
        do: {field, value}
  end

  defp lower_entry(%Entry{__kind__: kind} = entry) do
    fields = Authoring.dsl_fields(entry, Topology.schema(kind))

    case kind do
      :include ->
        Map.update!(fields, :bindings, &Enum.map(&1, fn binding -> lower_entry(binding) end))

      _ ->
        fields
    end
  end

  defp entry_sources(entry, path) do
    path = [:topology | path]
    sources = SourceMap.entity(entry, path)

    if entry.__kind__ == :include do
      SourceMap.collect([bindings: entry.bindings], sources, fn binding, nested ->
        SourceMap.entity(binding, path ++ nested)
      end)
    else
      sources
    end
  end
end
