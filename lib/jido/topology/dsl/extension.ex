for {module, kind, overrides} <- [
      {Jido.Topology.DSL.Agent, :agent, []},
      {Jido.Topology.DSL.Group, :group, [count: nil]},
      {Jido.Topology.DSL.Bus, :resource, []},
      {Jido.Topology.DSL.Owns, :owns, []},
      {Jido.Topology.DSL.Subscribe, :subscribe, []},
      {Jido.Topology.DSL.Include, :include, []},
      {Jido.Topology.DSL.Binding, :binding, []},
      {Jido.Topology.DSL.Import, :import, []},
      {Jido.Topology.DSL.Export, :export, []}
    ] do
  defmodule module do
    @moduledoc false
    defstruct Jido.Topology.DSL.Entity.struct_fields(kind, overrides)
  end
end

defmodule Jido.Topology.DSL.Extension do
  @moduledoc false
  alias Jido.Topology.DSL
  alias Jido.Topology.EntryMetadata
  alias Jido.Topology.DSL.Entity

  @agent %Spark.Dsl.Entity{
    name: :agent,
    target: DSL.Agent,
    args: [:key, {:optional, :module, nil}],
    schema: Entity.schema(EntryMetadata.schema(:agent))
  }
  @group %Spark.Dsl.Entity{
    name: :group,
    target: DSL.Group,
    args: [:key, {:optional, :module, nil}],
    schema:
      Entity.schema(
        Keyword.update!(EntryMetadata.schema(:group), :count, &Keyword.delete(&1, :default))
      )
  }
  @bus %Spark.Dsl.Entity{
    name: :bus,
    target: DSL.Bus,
    args: [:key],
    schema: Entity.schema(Keyword.delete(EntryMetadata.schema(:resource), :kind))
  }
  @owns %Spark.Dsl.Entity{
    name: :owns,
    target: DSL.Owns,
    args: [:parent, :child],
    schema: Entity.schema(EntryMetadata.schema(:owns))
  }
  @subscribe %Spark.Dsl.Entity{
    name: :subscribe,
    target: DSL.Subscribe,
    args: [:agent],
    schema: Entity.schema(EntryMetadata.schema(:subscribe))
  }

  @binding %Spark.Dsl.Entity{
    name: :bind,
    target: DSL.Binding,
    args: [:key],
    schema: Entity.schema(EntryMetadata.schema(:binding))
  }
  @include %Spark.Dsl.Entity{
    name: :include,
    target: DSL.Include,
    args: [:key, :topology],
    entities: [bindings: [@binding]],
    schema: Entity.schema(Keyword.delete(EntryMetadata.schema(:include), :bindings))
  }
  @import_bus %Spark.Dsl.Entity{
    name: :bus,
    target: DSL.Import,
    args: [:key],
    schema: Entity.schema(Keyword.delete(EntryMetadata.schema(:import), :kind))
  }
  @exports Enum.map([:agent, :group, :bus], fn kind ->
             %Spark.Dsl.Entity{
               name: kind,
               target: DSL.Export,
               args: [:key],
               auto_set_fields: [kind: kind],
               schema: Entity.schema(Keyword.delete(EntryMetadata.schema(:export), :kind))
             }
           end)

  @entity_sections Enum.map(
                     [
                       agents: [@agent, @group],
                       resources: [@bus],
                       relationships: [@owns],
                       connections: [@subscribe],
                       topologies: [@include],
                       imports: [@import_bus],
                       exports: @exports
                     ],
                     fn {name, entities} ->
                       %Spark.Dsl.Section{name: name, patchable?: true, entities: entities}
                     end
                   )
  @nested_startup_section %Spark.Dsl.Section{
    name: :startup,
    patchable?: true,
    schema:
      Enum.map(EntryMetadata.schema(:startup), fn {key, opts} ->
        {key, Keyword.delete(opts, :default)}
      end)
  }

  @topology_sections @entity_sections ++ [@nested_startup_section]

  @doc false
  def validate_metadata(value) do
    case Jido.Topology.Validation.plain_static_map(value) do
      {:ok, value} -> {:ok, value}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  use Spark.Dsl.Extension,
    persisters: [Jido.Topology.DSL.Compiler],
    sections: [
      %Spark.Dsl.Section{
        name: :topology,
        patchable?: true,
        schema: [
          schema: [
            type: {:custom, Jido.Agent.Authoring.Compiler, :validate_schema_storage, []},
            type_doc: "Zoi schema"
          ],
          metadata: [type: {:custom, __MODULE__, :validate_metadata, []}, type_doc: "map"]
        ],
        sections: @topology_sections
      }
    ]
end

defmodule Jido.Topology.DSL do
  @moduledoc false

  use Spark.Dsl,
    default_extensions: [
      extensions: [Jido.Agent.DSL.Extension, Jido.Topology.DSL.Extension]
    ]
end
