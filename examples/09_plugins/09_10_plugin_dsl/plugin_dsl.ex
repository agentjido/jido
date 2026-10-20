defmodule Jido.Examples.Plugins.DSL.Agent do
  @moduledoc "Uses a Plugin to add a threshold language to the Agent DSL."
  use Jido.Agent,
    name: "plugin_dsl_agent",
    extensions: [Jido.Examples.Plugins.DSL.Thresholds]

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  thresholds do
    on "examples.plugins.dsl.add"
    threshold :first, at: 1
    threshold :third, at: 3
  end

  routes do
    signal_source "/examples/plugins/dsl"

    route "examples.plugins.dsl.add", as: :add do
      action %{amount: amount}, schema: Zoi.object(%{amount: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end

  @doc "Allows stored data to select only installed, trusted code and known atoms."
  def registry do
    definition = definition()

    Jido.Authoring.Registry.new!(%{
      "agents/thresholds/v1" => {:agent, __MODULE__},
      "schemas/thresholds/v1" => {:schema, definition.schema},
      "actions/threshold-add/v1" => {:action, hd(definition.routes).handler.target},
      "plugins/thresholds/v1" => {:plugin, Jido.Examples.Plugins.DSL.Thresholds},
      "atoms/add" => {:atom, :add},
      "atoms/on" => {:atom, :on},
      "atoms/thresholds" => {:atom, :thresholds},
      "atoms/at" => {:atom, :at},
      "atoms/name" => {:atom, :name},
      "atoms/first" => {:atom, :first},
      "atoms/third" => {:atom, :third}
    })
  end
end
