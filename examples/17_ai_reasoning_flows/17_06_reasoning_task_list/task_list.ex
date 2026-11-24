defmodule Jido.Examples.AI.Reasoning.TaskList do
  @moduledoc "Defines the permitted tasks, their stored values, and the progress reply."

  alias Jido.Joi

  @titles %{
    "changes" => "List the release changes",
    "checks" => "Report the verification results",
    "release_notes" => "Check for release notes"
  }
  @task_id Joi.enum(Map.keys(@titles))
  @tasks Joi.list(
           Joi.object(%{
             id: @task_id,
             title: Joi.string(),
             status: Joi.enum([:pending, :in_progress, :completed]),
             result: Joi.string() |> Joi.nullable()
           })
         )
         |> Joi.max(3)

  def tasks_schema, do: @tasks

  def plan_schema do
    Joi.object(%{"tasks" => Joi.list(@task_id) |> Joi.min(1) |> Joi.max(3)}, unrecognized_keys: :error)
  end

  def task_titles, do: @titles

  def turn_output_schema do
    Joi.object(%{
      state: Joi.map(),
      response: Joi.object(%{tasks: @tasks, completed: Joi.integer(gte: 0), total: Joi.integer(gte: 0)})
    })
  end

  def turn_output(state) do
    %{
      state: state,
      response: %{
        tasks: state.tasks,
        completed: Enum.count(state.tasks, &(&1.status == :completed)),
        total: length(state.tasks)
      }
    }
  end
end
