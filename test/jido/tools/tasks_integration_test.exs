defmodule Jido.Tools.TasksIntegrationTest do
  use JidoTest.Case, async: true
  alias JidoTest.TestAgents.TaskManagementAgent
  alias Jido.Error

  @moduletag :capture_log

  describe "Task Management Integration" do
    setup do
      agent = TaskManagementAgent.new()
      {:ok, agent: agent}
    end

    test "creates and manages tasks through agent", %{agent: agent} do
      # Create initial task
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      {:ok, final, []} =
        TaskManagementAgent.cmd(
          agent,
          {Jido.Tools.Tasks.Create, %{title: "Initial Task", deadline: deadline}},
          %{},
          apply_state: true
        )

      assert map_size(final.state.tasks) == 1

      # Get the created task
      [{task_id, task}] = Enum.to_list(final.state.tasks)
      assert task.title == "Initial Task"
      assert task.deadline == deadline
      assert task.completed == false

      # Update the task
      new_deadline = DateTime.utc_now() |> DateTime.add(7200, :second)

      {:ok, updated, []} =
        TaskManagementAgent.cmd(
          final,
          {Jido.Tools.Tasks.Update,
           %{id: task_id, title: "Updated Task", deadline: new_deadline}},
          %{},
          apply_state: true
        )

      assert map_size(updated.state.tasks) == 1
      updated_task = updated.state.tasks[task_id]
      assert updated_task.id == task_id
      assert updated_task.title == "Updated Task"
      assert updated_task.deadline == new_deadline

      # Toggle task completion
      {:ok, toggled, []} =
        TaskManagementAgent.cmd(
          updated,
          {Jido.Tools.Tasks.Toggle, %{id: task_id}},
          %{},
          apply_state: true
        )

      assert map_size(toggled.state.tasks) == 1
      toggled_task = toggled.state.tasks[task_id]
      assert toggled_task.id == task_id
      assert toggled_task.completed == true

      # Delete the task
      {:ok, deleted, []} =
        TaskManagementAgent.cmd(
          toggled,
          {Jido.Tools.Tasks.Delete, %{id: task_id}},
          %{},
          apply_state: true
        )

      assert map_size(deleted.state.tasks) == 0
      assert is_nil(deleted.state.tasks[task_id])
    end

    test "handles multiple tasks", %{agent: agent} do
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      # Create multiple tasks in a single chain
      {:ok, final, []} =
        TaskManagementAgent.cmd(
          agent,
          [
            {Jido.Tools.Tasks.Create, %{title: "Task 1", deadline: deadline}},
            {Jido.Tools.Tasks.Create, %{title: "Task 2", deadline: deadline}},
            {Jido.Tools.Tasks.Create, %{title: "Task 3", deadline: deadline}}
          ],
          %{},
          apply_state: true
        )

      # Since state modifications are applied at the end, only the last task will be in the state
      assert map_size(final.state.tasks) == 1
      [{_id, task}] = Enum.to_list(final.state.tasks)
      assert task.title == "Task 1"

      # Create tasks one at a time to build up the state
      {:ok, with_task1, []} =
        TaskManagementAgent.cmd(
          agent,
          {Jido.Tools.Tasks.Create, %{title: "Task 1", deadline: deadline}},
          %{},
          apply_state: true
        )

      {:ok, with_task2, []} =
        TaskManagementAgent.cmd(
          with_task1,
          {Jido.Tools.Tasks.Create, %{title: "Task 2", deadline: deadline}},
          %{},
          apply_state: true
        )

      {:ok, with_task3, []} =
        TaskManagementAgent.cmd(
          with_task2,
          {Jido.Tools.Tasks.Create, %{title: "Task 3", deadline: deadline}},
          %{},
          apply_state: true
        )

      assert map_size(with_task3.state.tasks) == 3
      tasks = Enum.to_list(with_task3.state.tasks)
      task_titles = Enum.map(tasks, fn {_id, task} -> task.title end)
      assert Enum.sort(task_titles) == ["Task 1", "Task 2", "Task 3"]

      # Get task2 ID for update
      {task2_id, _} = Enum.find(tasks, fn {_id, task} -> task.title == "Task 2" end)

      # Update one task
      {:ok, updated, []} =
        TaskManagementAgent.cmd(
          with_task3,
          {Jido.Tools.Tasks.Update, %{id: task2_id, title: "Updated Task 2", deadline: deadline}},
          %{},
          apply_state: true
        )

      assert map_size(updated.state.tasks) == 3
      updated_tasks = Enum.to_list(updated.state.tasks)

      assert Enum.map(updated_tasks, fn {_id, task} -> task.title end) |> Enum.sort() ==
               ["Task 1", "Updated Task 2", "Task 3"] |> Enum.sort()

      # Get task1 ID for toggle
      {task1_id, _} = Enum.find(tasks, fn {_id, task} -> task.title == "Task 1" end)

      # Toggle another task
      {:ok, toggled, []} =
        TaskManagementAgent.cmd(
          updated,
          {Jido.Tools.Tasks.Toggle, %{id: task1_id}},
          %{},
          apply_state: true
        )

      assert map_size(toggled.state.tasks) == 3
      toggled_tasks = Enum.to_list(toggled.state.tasks)

      completed_statuses =
        Enum.map(toggled_tasks, fn {_id, task} -> task.completed end) |> Enum.sort()

      assert completed_statuses == [false, false, true]

      # Delete one task
      {:ok, deleted, []} =
        TaskManagementAgent.cmd(
          toggled,
          {Jido.Tools.Tasks.Delete, %{id: task2_id}},
          %{},
          apply_state: true
        )

      assert map_size(deleted.state.tasks) == 2
      deleted_tasks = Enum.to_list(deleted.state.tasks)

      assert Enum.map(deleted_tasks, fn {_id, task} -> task.title end) |> Enum.sort() ==
               ["Task 1", "Task 3"] |> Enum.sort()
    end

    test "handles errors gracefully", %{agent: agent} do
      # Try to update non-existent task
      {:error, error} =
        TaskManagementAgent.cmd(
          agent,
          {Jido.Tools.Tasks.Update,
           %{id: "non-existent", title: "New Title", deadline: DateTime.utc_now()}},
          %{},
          apply_state: true
        )

      assert Error.to_map(error).type == :execution_error
      assert error.message == :task_not_found
      assert map_size(agent.state.tasks) == 0

      # Try to toggle non-existent task
      {:error, error} =
        TaskManagementAgent.cmd(
          agent,
          {Jido.Tools.Tasks.Toggle, %{id: "non-existent"}},
          %{},
          apply_state: true
        )

      assert Error.to_map(error).type == :execution_error
      assert error.message == :task_not_found
      assert map_size(agent.state.tasks) == 0

      # Try to delete non-existent task
      {:error, error} =
        TaskManagementAgent.cmd(
          agent,
          {Jido.Tools.Tasks.Delete, %{id: "non-existent"}},
          %{},
          apply_state: true
        )

      assert Error.to_map(error).type == :execution_error
      assert error.message == :task_not_found
      assert map_size(agent.state.tasks) == 0
    end

    test "maintains task map integrity", %{agent: agent} do
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      # Create tasks one at a time to build up the state
      {:ok, with_task1, []} =
        TaskManagementAgent.cmd(
          agent,
          {Jido.Tools.Tasks.Create, %{title: "First", deadline: deadline}},
          %{},
          apply_state: true
        )

      {:ok, with_task2, []} =
        TaskManagementAgent.cmd(
          with_task1,
          {Jido.Tools.Tasks.Create, %{title: "Second", deadline: deadline}},
          %{},
          apply_state: true
        )

      {:ok, with_task3, []} =
        TaskManagementAgent.cmd(
          with_task2,
          {Jido.Tools.Tasks.Create, %{title: "Third", deadline: deadline}},
          %{},
          apply_state: true
        )

      # Get task IDs and verify initial state
      tasks = Enum.to_list(with_task3.state.tasks)
      task_ids = Enum.map(tasks, fn {id, task} -> {id, task.title} end)

      assert Enum.map(task_ids, fn {_id, title} -> title end) |> Enum.sort() ==
               ["First", "Second", "Third"] |> Enum.sort()

      # Get task2 ID for update
      {task2_id, _} = Enum.find(task_ids, fn {_id, title} -> title == "Second" end)

      # Update middle task
      {:ok, updated, []} =
        TaskManagementAgent.cmd(
          with_task3,
          {Jido.Tools.Tasks.Update, %{id: task2_id, title: "Updated Second", deadline: deadline}},
          %{},
          apply_state: true
        )

      # Verify update
      updated_tasks = Enum.to_list(updated.state.tasks)

      assert Enum.map(updated_tasks, fn {_id, task} -> task.title end) |> Enum.sort() ==
               ["First", "Updated Second", "Third"] |> Enum.sort()

      # Get task1 ID for toggle
      {task1_id, _} = Enum.find(task_ids, fn {_id, title} -> title == "First" end)

      # Toggle first task
      {:ok, toggled, []} =
        TaskManagementAgent.cmd(
          updated,
          {Jido.Tools.Tasks.Toggle, %{id: task1_id}},
          %{},
          apply_state: true
        )

      # Verify toggle and map integrity
      toggled_tasks = Enum.to_list(toggled.state.tasks)

      assert Enum.map(toggled_tasks, fn {_id, task} -> task.title end) |> Enum.sort() ==
               ["First", "Updated Second", "Third"] |> Enum.sort()

      # Verify the first task is completed
      first_task = Enum.find(toggled_tasks, fn {_id, task} -> task.title == "First" end)
      assert first_task != nil
      assert elem(first_task, 1).completed == true
    end
  end
end
