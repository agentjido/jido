defmodule Jido.Examples.Factory.WorkItem do
  @moduledoc "A temporary worker Agent for one item. It reports three timed steps to its factory manager."
  use Jido.Agent, name: "factory_work_item"

  agent do
    schema Zoi.object(%{
             job_id: Zoi.string() |> Zoi.default(""),
             goal: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             step: Zoi.integer() |> Zoi.min(0) |> Zoi.max(3) |> Zoi.default(0),
             step_delay_ms: Zoi.integer() |> Zoi.min(1) |> Zoi.default(2_000),
             started: Zoi.boolean() |> Zoi.default(false)
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/factory/work_item"

    route "examples.factory.work_item.start" do
      action _input, schema: Zoi.object(%{}), context: context do
        state = context.agent_state

        if state.started do
          {:ok, state}
        else
          {:ok, %{state | started: true}, [Jido.Examples.Factory.WorkItem.tick(state)]}
        end
      end

      define :start
    end

    route "examples.factory.work_item.tick" do
      action %{step: step},
        schema: Zoi.object(%{step: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2)}),
        context: context do
        Jido.Examples.Factory.WorkItem.advance(context.agent_state, step)
      end
    end
  end

  @doc false
  def tick(state) do
    signal =
      Jido.Signal.new!("examples.factory.work_item.tick", %{step: state.step},
        source: "/examples/factory/work_item/timer"
      )

    Jido.Plugin.Scheduler.schedule(state.step_delay_ms, signal)
  end

  @doc false
  def advance(%{started: true, step: step} = state, step) do
    progress =
      Jido.Signal.new!(
        "examples.factory.work_item.progress",
        %{job_id: state.job_id, generation: state.generation, step: step},
        source: "/examples/factory/work_item"
      )

    next = %{state | step: step + 1}
    directives = [Jido.Agent.Directive.emit_to_parent(progress)]
    directives = if next.step < 3, do: directives ++ [tick(next)], else: directives
    {:ok, next, directives}
  end

  def advance(_, _), do: Jido.Examples.Factory.Protocol.invalid("Worker tick is stale")
end
