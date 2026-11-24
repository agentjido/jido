defmodule Jido.Examples.AI.Reasoning.TaskList.Plan do
  @moduledoc "Asks the model for an ordered plan and validates it before changing the list."

  alias Jido.AI.InferenceClient.Selection
  alias Jido.Examples.AI.Reasoning.TaskList
  alias Jido.Joi
  alias ReqLLM.{Context, Response}

  @plan_schema TaskList.plan_schema()
  @model_schema ReqLLM.Schema.to_json(@plan_schema)

  use Jido.Flow,
    id: "jido.ai/examples/reasoning/task-list-plan",
    vsn: 1,
    name: "examples_ai_task_list_plan",
    schema: Joi.object(%{input: Joi.string() |> Joi.min(1) |> Joi.max(1_000)}, unrecognized_keys: :error),
    output_schema: TaskList.turn_output_schema()

  flow do
    step "propose_plan", brief <- input(:input), inline: [context: context] do
      client = Selection.client!(context)

      with {:ok, response} <-
             client.generate_object("openai:gpt-4o-mini", prompt(brief), @model_schema,
               max_tokens: 128,
               max_retries: 0,
               total_timeout: 5_000,
               output_validation: :strict
             ) do
        {:ok, %{plan: Response.object(response)}}
      end
    end

    step "accept_plan", plan <- result("propose_plan", :plan), inline: [context: context] do
      with {:ok, %{"tasks" => ids}} <- Joi.parse(@plan_schema, plan),
           :ok <- unique_tasks(ids) do
        tasks = Enum.map(ids, &new_task/1)
        {:ok, TaskList.turn_output(%{context.agent_state | tasks: tasks})}
      end
    end

    output result("accept_plan")
  end

  defp prompt(brief) do
    tasks = Enum.map_join(Enum.sort(TaskList.task_titles()), "\n", fn {id, title} -> "#{id} - #{title}" end)

    Context.new([
      Context.system("Select one to three different tasks for the release review. List them in work order.\n#{tasks}"),
      Context.user(brief)
    ])
  end

  defp unique_tasks(ids) do
    if Enum.uniq(ids) == ids, do: :ok, else: {:error, "The plan contains duplicate tasks."}
  end

  defp new_task(id) do
    %{id: id, title: Map.fetch!(TaskList.task_titles(), id), status: :pending, result: nil}
  end
end
