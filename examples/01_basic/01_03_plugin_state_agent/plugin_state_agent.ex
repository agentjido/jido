defmodule Jido.Examples.PluginStateAgent do
  @moduledoc """
  An Agent with state owned by a Plugin.

  CountTurns accepts one committed Turn. A second update exceeds its schema.
  The overwrite command deliberately breaks state ownership. Both rejection
  paths preserve the prior Agent state.
  """

  use Jido.Agent,
    name: "basic_sdk_plugin_state",
    plugins: [Jido.Examples.PluginStateAgent.CountTurns]

  state do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/basic/plugin_state_agent"

    route "basic.plugin_state.increment", as: :increment do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end

    route "basic.plugin_state.overwrite", as: :overwrite_plugin_state do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, %{context.agent_state | turns: context.agent_state.turns + 1}}
      end
    end
  end
end
