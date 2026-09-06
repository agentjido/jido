defmodule Jido.Examples.PluginStateAgent do
  @moduledoc """
  An Agent with state owned by a Plugin.

  CountTurns accepts one committed Turn. A second update exceeds its schema.
  The overwrite input deliberately breaks state ownership. Both rejection paths
  must preserve the prior Agent state and prevent Directive dispatch.
  """

  alias Jido.Examples.DirectiveAgent.{Effects, Record}

  defmodule CountTurns do
    use Jido.Plugin

    @impl true
    def state_spec(_opts),
      do: {:turns, Zoi.integer() |> Zoi.min(0) |> Zoi.max(1) |> Zoi.default(0)}

    @impl true
    def update_state(turns, _directives, _opts), do: {:ok, turns + 1}
  end

  defmodule Change do
    use Jido.Action,
      name: "basic_sdk_owned_state_change",
      schema:
        Zoi.object(%{
          amount: Zoi.integer(),
          overwrite?: Zoi.boolean() |> Zoi.default(false),
          observer: Zoi.pid()
        })

    @impl true
    def run(input, %{agent_state: state}) do
      send(input.observer, {:sdk_action, :change})
      candidate = %{state | count: state.count + input.amount}
      candidate = if input.overwrite?, do: %{candidate | turns: 1}, else: candidate
      {:ok, candidate, [%Record{label: "state accepted"}]}
    end
  end

  use Jido.Agent, name: "basic_sdk_plugin_state"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    plugin CountTurns
    plugin Effects
  end

  routes do
    signal_source "/examples/basic/plugin_state_agent"

    route "basic.owned.change", Change do
      define :increment, args: [:amount]
    end
  end
end
