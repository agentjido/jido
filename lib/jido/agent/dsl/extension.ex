defmodule Jido.Agent.DSL.Extension do
  @moduledoc false

  @plugin %Spark.Dsl.Entity{
    name: :__plugin__,
    target: Jido.Agent.DSL.Plugin,
    args: [:module, :__source__],
    modules: [:module],
    describe: "Declares one Agent plugin.",
    schema: [
      module: [type: :atom, required: true],
      as: [type: :atom],
      config: [type: :map, default: %{}],
      metadata: [type: :map, default: %{}],
      __source__: [type: :map, default: %{}]
    ]
  }

  @route %Spark.Dsl.Entity{
    name: :__route__,
    target: Jido.Agent.DSL.Route,
    args: [:path, :target, :__source__],
    modules: [:target],
    describe: "Declares one Agent signal route.",
    schema: [
      path: [type: :string, required: true],
      target: [type: :atom, required: true],
      match: [type: :any],
      priority: [type: :integer, default: 0],
      params: [type: :map, default: %{}],
      __source__: [type: :map, default: %{}]
    ]
  }

  @schedule %Spark.Dsl.Entity{
    name: :__schedule__,
    target: Jido.Agent.DSL.Schedule,
    args: [:name, :cron_expression, :signal_type, :__source__],
    describe: "Declares one named Agent schedule.",
    schema: [
      name: [type: :string, required: true],
      cron_expression: [type: :string, required: true],
      signal_type: [type: :string, required: true],
      timezone: [type: :string, default: "Etc/UTC"],
      data: [type: :map, default: %{}],
      metadata: [type: :map, default: %{}],
      __source__: [type: :map, default: %{}]
    ]
  }

  @agent %Spark.Dsl.Section{
    name: :agent,
    describe: "Declares one canonical Jido Agent.",
    imports: [Jido.Agent.DSL.Macros],
    schema: [
      name: [type: :string],
      description: [type: :string],
      state_schema: [type: :quoted],
      plugin_defaults: [type: :any],
      metadata: [type: :map]
    ],
    entities: [@plugin, @route, @schedule]
  }

  use Spark.Dsl.Extension, sections: [@agent]
end
