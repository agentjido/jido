defmodule Jido.Agent.DSL.Interface do
  @moduledoc false
  defstruct [:name, :__spark_metadata__, args: []]
end

defmodule Jido.Agent.DSL.Route do
  @moduledoc false
  defstruct [:path, :target, :defaults, :match, :__spark_metadata__, priority: 0, interfaces: []]
end

defmodule Jido.Agent.DSL.Plugin do
  @moduledoc false
  defstruct [:module, :__spark_metadata__, config: []]
end

defmodule Jido.Agent.DSL.Extension do
  @moduledoc false

  @interface %Spark.Dsl.Entity{
    name: :define,
    target: Jido.Agent.DSL.Interface,
    args: [:name],
    schema: [name: [type: :atom, required: true], args: [type: :any, default: []]]
  }
  @route %Spark.Dsl.Entity{
    name: :__route__,
    target: Jido.Agent.DSL.Route,
    args: [:path, {:optional, :target}],
    entities: [interfaces: [@interface]],
    schema: [
      path: [type: :string, required: true],
      target: [type: :any],
      defaults: [type: :map],
      priority: [type: :integer, default: 0],
      match: [type: {:fun, 1}]
    ]
  }
  @plugin %Spark.Dsl.Entity{
    name: :plugin,
    target: Jido.Agent.DSL.Plugin,
    args: [:module],
    schema: [
      module: [type: :atom, required: true],
      config: [type: :any, default: []]
    ]
  }
  @agent %Spark.Dsl.Section{
    name: :agent,
    schema: [schema: [type: :any], metadata: [type: :map]],
    entities: [@plugin]
  }
  @routes %Spark.Dsl.Section{
    name: :routes,
    schema: [signal_source: [type: :string]],
    imports: [Jido.Agent.DSL.Macros],
    entities: [@route]
  }

  use Spark.Dsl.Extension, sections: [@agent, @routes]
end

defmodule Jido.Agent.DSL do
  @moduledoc false
  use Spark.Dsl, default_extensions: [extensions: [Jido.Agent.DSL.Extension]]
end
