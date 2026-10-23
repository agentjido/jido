defmodule JidoTest.AgentRuntimeFixtures.ReturnDirective do
  @moduledoc false
  use Jido.Action, name: "agent_return_directive", output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{event: event} = params, context) do
    state = context.agent_state
    directives = Map.get(params, :directives) || [Map.fetch!(params, :directive)]
    {:ok, %{state | events: state.events ++ [event]}, directives}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.Record do
  @moduledoc false
  use Jido.Action, name: "agent_runtime_record", output_schema: Zoi.map()

  @impl Jido.Action
  def run(params, context) do
    event = Map.get(params, :event, params)
    state = context.agent_state
    {:ok, %{state | events: state.events ++ [event]}}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.Tick do
  @moduledoc false
  use Jido.Action, name: "agent_runtime_tick", output_schema: Zoi.map()

  @impl Jido.Action
  def run(_params, context) do
    state = context.agent_state
    {:ok, %{state | ticks: state.ticks + 1}}
  end
end

defmodule JidoTest.AgentRuntimeFixtures.RuntimeAgent do
  @moduledoc false

  alias JidoTest.AgentRuntimeFixtures.{Record, ReturnDirective, Tick}

  use Jido.Agent, name: "runtime_agent"

  state do
    schema Zoi.object(%{
             events: Zoi.list(Zoi.any()) |> Zoi.default([]),
             ticks: Zoi.integer() |> Zoi.default(0)
           })
  end

  plugins do
    plugin Jido.Plugin.Scheduler
  end

  routes do
    route "runtime.directive", ReturnDirective do
      state(from: output())
    end

    route "runtime.record", Record do
      state(from: output())
    end

    route "cron.tick", Tick do
      state(from: output())
    end

    route "jido.agent.child.started", Record do
      state(from: output())
    end

    route "jido.agent.child.exit", Record do
      state(from: output())
    end

    route "jido.agent.orphaned", Record do
      state(from: output())
    end
  end
end
