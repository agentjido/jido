defmodule Jido.Examples.PluginIsolation.Counter do
  @moduledoc "Keeps domain state and Plugin-owned state in one protected state map."
  use Jido.Agent, name: "research_plugin_isolation"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(10)})
    plugin Jido.Examples.PluginIsolation.Owned
  end

  routes do
    signal_source "/examples/research/plugin_isolation"

    route "examples.research.plugin_isolation.order.audit" do
      action input,
        schema:
          Zoi.object(%{
            amount: Zoi.integer() |> Zoi.default(1),
            overwrite_owned: Zoi.boolean() |> Zoi.default(false)
          }),
        context: context do
        state = Map.update!(context.agent_state, :total, &(&1 + input.amount))
        state = if input.overwrite_owned, do: %{state | audit: 99}, else: state
        {:ok, state}
      end
    end
  end
end

defmodule Jido.Examples.PluginIsolation.Owned.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.Agent.Plugin.Reduction

  def state_spec(_opts), do: {:audit, Zoi.integer() |> Zoi.default(0)}
  def reduce(%Reduction{plugin_state: state}, _opts), do: {:ok, state + 1}
end

defmodule Jido.Examples.PluginIsolation.Owned do
  @moduledoc "Owns the protected audit counter."
  use Jido.Plugin, agent: Jido.Examples.PluginIsolation.Owned.Agent
end

defmodule Jido.Examples.PluginIsolation do
  @moduledoc "Shows post-execution Plugin state reduction and owned-state protection."
  alias __MODULE__.Counter

  def new, do: Counter.new!(id: "audit-order")

  def signal(data \\ %{}) do
    Jido.Signal.new!(
      "examples.research.plugin_isolation.order.audit",
      data,
      source: "/examples/research/plugin_isolation"
    )
  end
end
