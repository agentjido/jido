defmodule Jido.Examples.Applications.FixedGroup.WorkerAgent do
  @moduledoc "Handles work that targets its stable member identity."
  use Jido.Agent, name: "fixed_group_worker"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.Signals

  @dispatch {:bus, [target: :fixed_group_bus]}

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             member_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             handled: Zoi.list(Zoi.string()) |> Zoi.default([]),
             ignored: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [
        bus: :fixed_group_bus,
        paths: ["examples.applications.fixed_group.work.requested"]
      ]
  end

  routes do
    signal_source "/examples/applications/fixed_group/worker"

    route "examples.applications.fixed_group.work.requested" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            target_id: Zoi.string(),
            task_id: Zoi.string(),
            value: Zoi.integer()
          }),
        context: context do
        state = context.agent_state

        if input.group_id == state.group_id and input.generation == state.generation and
             input.target_id == state.member_id do
          signal =
            Signals.environment_apply(
              state.group_id,
              state.generation,
              state.member_id,
              input.task_id,
              input.value * 2
            )

          next_state = %{state | handled: state.handled ++ [input.task_id]}
          {:ok, next_state, [Directive.emit(signal, @dispatch)]}
        else
          {:ok, %{state | ignored: state.ignored + 1}}
        end
      end
    end
  end
end
