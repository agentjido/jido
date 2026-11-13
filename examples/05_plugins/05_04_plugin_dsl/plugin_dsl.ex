defmodule Jido.Examples.Plugins.DSL.Agent do
  @moduledoc "Uses a Plugin to add a threshold language to the Agent DSL."
  use Jido.Agent,
    name: "plugin_dsl_agent",
    plugins: [Jido.Examples.Plugins.DSL.Thresholds]

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  thresholds do
    on "examples.plugins.dsl.add"
    threshold :first, at: 1
    threshold :third, at: 3
  end

  routes do
    signal_source "/examples/plugins/dsl"

    route "examples.plugins.dsl.add", as: :add do
      action %{amount: amount},
        schema: Jido.Joi.object(%{amount: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end

  @doc "Allows stored data to select only installed, trusted code and known atoms."
  def registry do
    definition = definition()

    Jido.Catalog.from_targets!(__MODULE__, :jido, %{
      {"agents/thresholds", 1} => __MODULE__,
      {"schemas/thresholds", 1} => definition.schema,
      {"actions/threshold-add", 1} => hd(definition.routes).handler.target,
      {"plugins/thresholds", 1} => Jido.Examples.Plugins.DSL.Thresholds,
      {"atoms/add", 1} => :add,
      {"atoms/on", 1} => :on,
      {"atoms/thresholds", 1} => :thresholds,
      {"atoms/at", 1} => :at,
      {"atoms/name", 1} => :name,
      {"atoms/first", 1} => :first,
      {"atoms/third", 1} => :third
    })
  end
end
