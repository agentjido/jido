defmodule Jido.Topology.DSL.Agent do
  @moduledoc false
  defstruct [:key, :module, :__spark_metadata__, initial_state: %{}, depends_on: []]
end

defmodule Jido.Topology.DSL.Group do
  @moduledoc false
  defstruct [
    :key,
    :module,
    :count,
    :members,
    :key_by,
    :__spark_metadata__,
    initial_state: %{},
    depends_on: []
  ]
end

defmodule Jido.Topology.DSL.Bus do
  @moduledoc false
  defstruct [:key, :__spark_metadata__, config: []]
end

defmodule Jido.Topology.DSL.Owns do
  @moduledoc false
  defstruct [:parent, :child, :__spark_metadata__, on_parent_exit: :stop]
end

defmodule Jido.Topology.DSL.Subscribe do
  @moduledoc false
  defstruct [:agent, :to, :path, :__spark_metadata__]
end

defmodule Jido.Topology.DSL.Include do
  @moduledoc false
  defstruct [:key, :topology, :__spark_metadata__, inputs: %{}, bindings: []]
end

defmodule Jido.Topology.DSL.Binding do
  @moduledoc false
  defstruct [:key, :to, :__spark_metadata__]
end

defmodule Jido.Topology.DSL.Import do
  @moduledoc false
  defstruct [:key, :__spark_metadata__, kind: :bus]
end

defmodule Jido.Topology.DSL.Export do
  @moduledoc false
  defstruct [:key, :kind, :from, :__spark_metadata__]
end

defmodule Jido.Topology.DSL.Extension do
  @moduledoc false
  alias Jido.Topology.DSL

  @agent_fields [
    key: [type: :any, required: true],
    module: [type: :atom, required: true],
    initial_state: [type: :any, default: %{}],
    depends_on: [type: {:list, :any}, default: []]
  ]
  @agent %Spark.Dsl.Entity{
    name: :agent,
    target: DSL.Agent,
    args: [:key, :module],
    schema: @agent_fields
  }
  @group %Spark.Dsl.Entity{
    name: :group,
    target: DSL.Group,
    args: [:key, :module],
    schema: @agent_fields ++ [count: [type: :any], members: [type: :any], key_by: [type: :any]]
  }
  @bus %Spark.Dsl.Entity{
    name: :bus,
    target: DSL.Bus,
    args: [:key],
    schema: [key: [type: :any, required: true], config: [type: :any, default: []]]
  }
  @owns %Spark.Dsl.Entity{
    name: :owns,
    target: DSL.Owns,
    args: [:parent, :child],
    schema: [
      parent: [type: :any, required: true],
      child: [type: :any, required: true],
      on_parent_exit: [type: {:in, [:stop, :continue, :emit_orphan]}, default: :stop]
    ]
  }
  @subscribe %Spark.Dsl.Entity{
    name: :subscribe,
    target: DSL.Subscribe,
    args: [:agent],
    schema: [
      agent: [type: :any, required: true],
      to: [type: :any, required: true],
      path: [type: :string, required: true]
    ]
  }

  @binding %Spark.Dsl.Entity{
    name: :bind,
    target: DSL.Binding,
    args: [:key],
    schema: [key: [type: :any, required: true], to: [type: :any, required: true]]
  }
  @include %Spark.Dsl.Entity{
    name: :include,
    target: DSL.Include,
    args: [:key, :topology],
    entities: [bindings: [@binding]],
    schema: [
      key: [type: :any, required: true],
      topology: [type: :any, required: true],
      inputs: [type: :map, default: %{}]
    ]
  }
  @import_bus %Spark.Dsl.Entity{
    name: :bus,
    target: DSL.Import,
    args: [:key],
    schema: [key: [type: :any, required: true]]
  }
  @exports Enum.map([:agent, :group, :bus], fn kind ->
             %Spark.Dsl.Entity{
               name: kind,
               target: DSL.Export,
               args: [:key],
               auto_set_fields: [kind: kind],
               schema: [key: [type: :any, required: true], from: [type: :any, required: true]]
             }
           end)

  use Spark.Dsl.Extension,
    sections: [
      %Spark.Dsl.Section{name: :topology, schema: [schema: [type: :any], metadata: [type: :map]]},
      %Spark.Dsl.Section{name: :agents, entities: [@agent, @group]},
      %Spark.Dsl.Section{name: :resources, entities: [@bus]},
      %Spark.Dsl.Section{name: :relationships, entities: [@owns]},
      %Spark.Dsl.Section{name: :connections, entities: [@subscribe]},
      %Spark.Dsl.Section{name: :topologies, entities: [@include]},
      %Spark.Dsl.Section{name: :imports, entities: [@import_bus]},
      %Spark.Dsl.Section{name: :exports, entities: @exports},
      %Spark.Dsl.Section{
        name: :startup,
        schema: [
          concurrency: [type: :pos_integer],
          ready: [type: {:in, [:all]}],
          max_agents: [type: :pos_integer],
          retry_interval: [type: :pos_integer],
          task_timeout: [type: :pos_integer]
        ]
      }
    ]
end

defmodule Jido.Topology.DSL do
  @moduledoc false
  use Spark.Dsl, default_extensions: [extensions: [Jido.Topology.DSL.Extension]]
end
