defmodule Jido.Agent.DSL.Entry do
  @moduledoc false
  defstruct [
    :path,
    :handler,
    :as,
    :name,
    :provider,
    :config,
    :definition,
    :from,
    :to,
    :__spark_metadata__,
    defaults: %{},
    count: 1,
    initial_state: %{},
    delivery: :single
  ]
end

defmodule Jido.Agent.DSL.Extension do
  @moduledoc false
  alias Jido.Agent.DSL.Entry

  @plugin %Spark.Dsl.Entity{
    name: :plugin,
    target: Entry,
    args: [:provider],
    schema: [provider: [type: :atom, required: true], config: [type: :any, default: %{}]]
  }
  @agent %Spark.Dsl.Section{
    name: :__agent__,
    schema: [schema: [type: :any], metadata: [type: :any, default: %{}]],
    entities: [@plugin]
  }
  @route %Spark.Dsl.Entity{
    name: :__route__,
    target: Entry,
    args: [:path, :handler],
    schema: [
      path: [type: :string, required: true],
      handler: [type: :any, required: true],
      as: [type: :atom],
      defaults: [type: :any, default: %{}]
    ]
  }
  @routes %Spark.Dsl.Section{
    name: :__routes__,
    imports: [Jido.Agent.DSL.RouteMacros],
    entities: [@route],
    schema: [signal_source: [type: :string]]
  }
  use Spark.Dsl.Extension, sections: [@agent, @routes]
end
