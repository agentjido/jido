defmodule Jido.Agent.DSL.Entry do
  @moduledoc false
  defstruct [
    :path,
    :handler,
    :state,
    :reply,
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

  @state %Spark.Dsl.Section{
    name: :__state__,
    schema: [schema: [type: :any], initial_state: [type: :any, default: %{}]]
  }
  @route %Spark.Dsl.Entity{
    name: :__route__,
    target: Entry,
    args: [:path, :handler],
    schema: [
      path: [type: :string, required: true],
      handler: [type: :any, required: true],
      state: [type: :any, default: %{source: :output, path: []}],
      reply: [type: :any, default: nil],
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
  use Spark.Dsl.Extension, sections: [@state, @routes]
end
