defmodule Jido.Examples.Applications.FixedGroup.EnvironmentAgent do
  @moduledoc "Applies each task result once and publishes the committed result."
  use Jido.Agent, name: "fixed_group_environment"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.Signals

  @dispatch {:bus, [target: :fixed_group_bus]}

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             results: Zoi.map() |> Zoi.default(%{}),
             duplicates: Zoi.integer() |> Zoi.default(0),
             ignored: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [
        bus: :fixed_group_bus,
        paths: ["examples.applications.fixed_group.environment.apply"]
      ]
  end

  routes do
    signal_source "/examples/applications/fixed_group/environment"

    route "examples.applications.fixed_group.environment.apply" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            worker_id: Zoi.string(),
            task_id: Zoi.string(),
            result: Zoi.integer()
          }),
        context: context do
        state = context.agent_state

        cond do
          input.group_id != state.group_id or input.generation != state.generation ->
            {:ok, %{state | ignored: state.ignored + 1}}

          Map.has_key?(state.results, input.task_id) ->
            {:ok, %{state | duplicates: state.duplicates + 1}}

          true ->
            result = %{
              task_id: input.task_id,
              worker_id: input.worker_id,
              result: input.result
            }

            next_state = %{state | results: Map.put(state.results, input.task_id, result)}

            applied =
              Signals.work_applied(%{
                group_id: state.group_id,
                generation: state.generation,
                task_id: input.task_id,
                worker_id: input.worker_id,
                result: input.result
              })

            {:ok, next_state, [Directive.emit(applied, @dispatch)]}
        end
      end
    end
  end
end
