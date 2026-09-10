defmodule Jido.Examples.PluginIsolation.Owned.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  def state_spec(_), do: {:audit, Zoi.integer() |> Zoi.default(0)}
  def update_state(state, _directives, _opts), do: {:ok, state + 1}
end

defmodule Jido.Examples.PluginIsolation.Owned do
  @moduledoc false
  use Jido.Plugin, agent: Jido.Examples.PluginIsolation.Owned.Agent
end

defmodule Jido.Examples.PluginIsolation.Record do
  @moduledoc false
  use Jido.Action,
    name: "research_plugin_record",
    schema:
      Zoi.object(%{
        amount: Zoi.integer() |> Zoi.default(1),
        overwrite_owned: Zoi.boolean() |> Zoi.default(false)
      })

  def run(input, context) do
    state = Map.update!(context.agent_state, :total, &(&1 + input.amount))

    state = if input.overwrite_owned, do: %{state | audit: 99}, else: state
    {:ok, state}
  end
end

defmodule Jido.Examples.PluginIsolation.Counter do
  @moduledoc "Keeps domain state and Plugin-owned state in one protected state map."
  use Jido.Agent, name: "research_plugin_isolation"
  alias Jido.Examples.PluginIsolation.{Owned, Record}

  agent do
    schema Zoi.object(%{
             total: Zoi.integer() |> Zoi.default(10)
           })

    plugin Owned
  end

  routes do
    signal_source "/examples/plugin-isolation"
    route "order.audit", Record
  end
end

defmodule Jido.Examples.PluginIsolation do
  @moduledoc "Shows post-execution Plugin state reduction and owned-state protection."
  alias __MODULE__.Counter

  def new, do: Counter.new!(id: "audit-order")

  def signal(data \\ %{}),
    do: Jido.Signal.new!("order.audit", data, source: "/examples/plugin-isolation")
end
