defmodule Jido.Examples.PluginStateAgent do
  @moduledoc """
  An Agent with state owned by a Plugin.

  CountTurns accepts one committed Turn. A second update exceeds its schema.
  The overwrite command deliberately breaks state ownership. Both rejection
  paths preserve the prior Agent state.
  """

  defmodule CountTurns do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule CountTurns.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts),
      do: {:turns, Zoi.integer() |> Zoi.min(0) |> Zoi.max(1) |> Zoi.default(0)}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
  end

  use Jido.Agent, name: "basic_sdk_plugin_state"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin CountTurns
  end

  routes do
    signal_source "/examples/basic/plugin_state_agent"

    route "basic.plugin_state.increment" do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end

      define :increment, args: [:amount]
    end

    route "basic.plugin_state.overwrite" do
      action _input,
        schema: Zoi.object(%{}),
        context: context do
        {:ok, %{context.agent_state | turns: context.agent_state.turns + 1}}
      end

      define :overwrite_plugin_state
    end
  end
end
