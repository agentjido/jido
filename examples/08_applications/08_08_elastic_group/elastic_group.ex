defmodule Jido.Examples.Applications.ElasticGroup.ControllerAgent do
  @moduledoc "Owns an application-managed worker group that scales with queued demand."
  use Jido.Agent, name: "elastic_group_controller"

  alias Jido.Examples.Applications.ElasticGroup.ControllerState

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             min_workers: Zoi.integer() |> Zoi.default(2),
             max_workers: Zoi.integer() |> Zoi.default(5),
             next_worker_index: Zoi.integer() |> Zoi.default(1),
             desired_workers: Zoi.list(Zoi.string()) |> Zoi.default([]),
             worker_indexes: Zoi.map() |> Zoi.default(%{}),
             worker_status: Zoi.map() |> Zoi.default(%{}),
             draining_workers: Zoi.list(Zoi.string()) |> Zoi.default([]),
             queue: Zoi.list(Zoi.map()) |> Zoi.default([]),
             in_flight: Zoi.map() |> Zoi.default(%{}),
             results: Zoi.map() |> Zoi.default(%{}),
             low_observations: Zoi.integer() |> Zoi.default(0),
             scale_down_observations: Zoi.integer() |> Zoi.default(2),
             persistent_members: Zoi.list(Zoi.string()) |> Zoi.default([]),
             member_starts: Zoi.map() |> Zoi.default(%{}),
             exits: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [
        bus: :elastic_group_bus,
        paths: [
          "examples.applications.elastic_group.work.completed",
          "examples.applications.elastic_group.control.worker.drained"
        ]
      ]
  end

  routes do
    signal_source "/examples/applications/elastic_group/controller"

    route "examples.applications.elastic_group.start" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string() |> Zoi.min(1),
            min_workers: Zoi.integer() |> Zoi.min(1),
            max_workers: Zoi.integer() |> Zoi.min(1)
          }),
        context: context do
        ControllerState.start(input, context.agent_state)
      end

      define :start, args: [:group_id, :min_workers, :max_workers]
    end

    route "jido.agent.child.started" do
      action input,
        schema: Zoi.object(%{child_id: Zoi.string(), meta: Zoi.map()}),
        context: context do
        ControllerState.member_started(input, context.agent_state)
      end
    end

    route "jido.agent.child.exit" do
      action input,
        schema: Zoi.object(%{child_id: Zoi.string(), reason: Zoi.any()}),
        context: context do
        ControllerState.child_exit(input, context.agent_state)
      end
    end

    route "examples.applications.elastic_group.tasks.enqueue" do
      action input,
        schema:
          Zoi.object(%{
            tasks:
              Zoi.list(
                Zoi.object(%{
                  id: Zoi.string() |> Zoi.min(1),
                  value: Zoi.integer(),
                  delay_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
                  retry_delay_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.optional()
                })
              )
          }),
        context: context do
        ControllerState.enqueue(input, context.agent_state)
      end

      define :enqueue, args: [:tasks]
    end

    route "examples.applications.elastic_group.work.completed" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            task_id: Zoi.string(),
            worker_id: Zoi.string(),
            attempt: Zoi.integer(),
            result: Zoi.integer()
          }),
        context: context do
        ControllerState.record_completion(input, context.agent_state)
      end
    end

    route "examples.applications.elastic_group.scale.observe" do
      action _input, context: context do
        ControllerState.observe_scale(context.agent_state)
      end

      define :observe_scale
    end

    route "examples.applications.elastic_group.control.worker.drained" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            member_id: Zoi.string()
          }),
        context: context do
        ControllerState.record_drained(input, context.agent_state)
      end
    end
  end
end
