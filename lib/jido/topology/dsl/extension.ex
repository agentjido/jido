defmodule Jido.Topology.DSL.Agent do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:agent)
end

defmodule Jido.Topology.DSL.Group do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:group, count: nil)
end

defmodule Jido.Topology.DSL.Bus do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:resource)
end

defmodule Jido.Topology.DSL.Owns do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:owns)
end

defmodule Jido.Topology.DSL.Subscribe do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:subscribe)
end

defmodule Jido.Topology.DSL.Include do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:include)
end

defmodule Jido.Topology.DSL.Binding do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:binding)
end

defmodule Jido.Topology.DSL.Import do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:import)
end

defmodule Jido.Topology.DSL.Export do
  @moduledoc false
  defstruct Jido.Topology.DSL.Entity.struct_fields(:export)
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

  @agents_section %Spark.Dsl.Section{
    name: :agents,
    patchable?: true,
    entities: [@agent, @group]
  }
  @resources_section %Spark.Dsl.Section{name: :resources, patchable?: true, entities: [@bus]}
  @relationships_section %Spark.Dsl.Section{
    name: :relationships,
    patchable?: true,
    entities: [@owns]
  }
  @connections_section %Spark.Dsl.Section{
    name: :connections,
    patchable?: true,
    entities: [@subscribe]
  }
  @topologies_section %Spark.Dsl.Section{
    name: :topologies,
    patchable?: true,
    entities: [@include]
  }
  @imports_section %Spark.Dsl.Section{
    name: :imports,
    patchable?: true,
    entities: [@import_bus]
  }
  @exports_section %Spark.Dsl.Section{name: :exports, patchable?: true, entities: @exports}
  @nested_startup_section %Spark.Dsl.Section{
    name: :startup,
    patchable?: true,
    schema:
      Enum.map(EntryMetadata.schema(:startup), fn {key, opts} ->
        {key, Keyword.delete(opts, :default)}
      end)
  }

  @entity_sections [
    @agents_section,
    @resources_section,
    @relationships_section,
    @connections_section,
    @topologies_section,
    @imports_section,
    @exports_section
  ]
  @topology_sections @entity_sections ++ [@nested_startup_section]

  @doc false
  def validate_metadata(value) do
    case Jido.Topology.Validation.field(:metadata, value) do
      :ok -> {:ok, value}
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
          schema: [type: :any],
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
