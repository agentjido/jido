defmodule Jido.Examples.AI.Reasoning.TaskList.Agent do
  @moduledoc "Stores a model-selected release review plan and the results of its tasks."

  alias Jido.Joi
  alias Jido.Examples.AI.Reasoning.TaskList
  alias TaskList.{Plan, Work}

  use Jido.Agent,
    name: "examples_ai_reasoning_task_list",
    id: "jido.ai/examples/agents/reasoning-task-list",
    vsn: 1,
    plugins: [Jido.AI.Agent.Plugin]

  import Jido.AI.Agent.Plugin, only: [ai: 1, reasoning: 1]

  state do
    schema Joi.object(%{
             tasks: TaskList.tasks_schema() |> Joi.default([]),
             release:
               Joi.object(%{
                 changes: Joi.list(Joi.string()),
                 checks_passed: Joi.integer(gte: 0),
                 checks_failed: Joi.integer(gte: 0),
                 release_notes_present: Joi.boolean()
               })
           })
  end

  ai do
    reasoning Plan
  end

  routes do
    signal_source "/examples/ai/reasoning/task-list"

    route "examples.ai.reasoning.task_list.advance", Work, as: :advance do
      state(from: output(:state))
      reply("examples.ai.reasoning.task_list.progress", from: output(:response))
    end
  end
end
