defmodule Jido.Examples.AI.Reasoning.TaskList.Work do
  @moduledoc "Finishes the active task and starts the next one in the same Turn."

  alias Jido.Examples.AI.Reasoning.TaskList
  alias Jido.Joi

  use Jido.Flow,
    id: "jido.ai/examples/reasoning/task-list-work",
    vsn: 1,
    name: "examples_ai_task_list_work",
    schema: Joi.object(%{}, unrecognized_keys: :error),
    output_schema: TaskList.turn_output_schema()

  flow do
    step "complete_active", [], inline: [context: context] do
      %{release: release, tasks: tasks} = context.agent_state

      tasks =
        update_first(tasks, :in_progress, fn task ->
          %{task | status: :completed, result: run_task(task.id, release)}
        end)

      {:ok, %{tasks: tasks}}
    end

    step "start_next", tasks <- result("complete_active", :tasks), inline: [context: context] do
      tasks = update_first(tasks, :pending, &%{&1 | status: :in_progress})
      {:ok, TaskList.turn_output(%{context.agent_state | tasks: tasks})}
    end

    output result("start_next")
  end

  defp update_first(tasks, status, update) do
    case Enum.find_index(tasks, &(&1.status == status)) do
      nil -> tasks
      index -> List.update_at(tasks, index, update)
    end
  end

  defp run_task("changes", release), do: Enum.join(release.changes, ", ")

  defp run_task("checks", release) do
    "#{release.checks_passed} passed, #{release.checks_failed} failed."
  end

  defp run_task("release_notes", %{release_notes_present: true}), do: "Release notes are present."
  defp run_task("release_notes", %{release_notes_present: false}), do: "Release notes are missing."
end
