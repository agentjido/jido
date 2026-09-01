defmodule Jido.DocsRoutingGuidesTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.Signal

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "docs_increment",
      schema: [amount: [type: :integer, default: 1]]

    @impl true
    def run(params, context) do
      current = context.state[:count] || 0
      {:ok, %{count: current + params.amount}}
    end
  end

  defmodule DecrementAction do
    @moduledoc false
    use Jido.Action,
      name: "docs_decrement",
      schema: [amount: [type: :integer, default: 1]]

    @impl true
    def run(params, context) do
      current = context.state[:count] || 0
      {:ok, %{count: current - params.amount}}
    end
  end

  defmodule ResetAction do
    @moduledoc false
    use Jido.Action,
      name: "docs_reset",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{count: 0}}
  end

  defmodule CounterAgent do
    @moduledoc false
    use Jido.Agent,
      name: "docs_counter_agent",
      schema: [count: [type: :integer, default: 0]],
      signal_routes: [
        {"counter.increment", Jido.DocsRoutingGuidesTest.IncrementAction},
        {"counter.decrement", Jido.DocsRoutingGuidesTest.DecrementAction},
        {"counter.reset", Jido.DocsRoutingGuidesTest.ResetAction}
      ]
  end

  defmodule PluginIncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "docs_plugin_increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    @impl true
    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter, :value]) || 0

      {:ok, %{},
       [
         %Jido.Agent.StateOp.SetPath{path: [:counter, :value], value: current + amount}
       ]}
    end
  end

  defmodule CounterPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "counter",
      state_key: :counter,
      actions: [Jido.DocsRoutingGuidesTest.PluginIncrementAction],
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
      signal_routes: [
        {"increment", Jido.DocsRoutingGuidesTest.PluginIncrementAction}
      ]
  end

  defmodule PluginAgent do
    @moduledoc false
    use Jido.Agent,
      name: "docs_plugin_agent",
      plugins: [Jido.DocsRoutingGuidesTest.CounterPlugin]
  end

  test "Getting Started agent routes complete signal types to Actions", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, CounterAgent, id: unique_id("docs-counter"))

    {:ok, agent} =
      AgentServer.call(
        pid,
        Signal.new!("counter.increment", %{amount: 10}, source: "/test")
      )

    assert agent.state.count == 10

    {:ok, agent} =
      AgentServer.call(
        pid,
        Signal.new!("counter.decrement", %{amount: 3}, source: "/test")
      )

    assert agent.state.count == 7

    :ok = AgentServer.cast(pid, Signal.new!("counter.reset", %{}, source: "/test"))

    state = eventually_state(pid, fn state -> state.agent.state.count == 0 end)
    assert state.agent.state.count == 0
  end

  test "Your First Plugin expands relative static routes", %{jido: jido} do
    assert {"counter.increment", PluginIncrementAction, -10} in PluginAgent.plugin_routes()

    {:ok, pid} = Jido.start_agent(jido, PluginAgent, id: unique_id("docs-plugin"))

    {:ok, agent} =
      AgentServer.call(
        pid,
        Signal.new!("counter.increment", %{amount: 5}, source: "/test")
      )

    assert agent.state.counter.value == 5
  end
end
