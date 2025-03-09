defmodule Jido.Actions.TasksTest do
  use JidoTest.Case, async: true
  alias Jido.Actions.Tasks
  alias Jido.Actions.Tasks.Task
  alias Jido.Agent.Directive.StateModification

  @moduletag :capture_log

  describe "CreateTask" do
    test "creates a new task with valid parameters" do
      title = "Test Task"
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      assert {:ok, task, [%StateModification{} = directive]} =
               Tasks.CreateTask.run(%{title: title, deadline: deadline}, %{state: %{tasks: %{}}})

      assert %Task{
               id: task_id,
               title: ^title,
               completed: false,
               created_at: created_at,
               deadline: ^deadline
             } = task

      assert is_binary(task_id)
      assert DateTime.diff(created_at, DateTime.utc_now()) < 1

      # Verify directive
      assert directive.op == :set
      assert directive.path == [:tasks]
      assert map_size(directive.value) == 1
      assert directive.value[task_id] == task
    end

    test "creates multiple tasks" do
      title1 = "First Task"
      title2 = "Second Task"
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      {:ok, _task1, [%StateModification{value: tasks1}]} =
        Tasks.CreateTask.run(%{title: title1, deadline: deadline}, %{state: %{tasks: %{}}})

      {:ok, _task2, [%StateModification{value: tasks2}]} =
        Tasks.CreateTask.run(%{title: title2, deadline: deadline}, %{state: %{tasks: tasks1}})

      assert map_size(tasks2) == 2

      assert Enum.map(tasks2, fn {_id, task} -> task.title end) |> Enum.sort() ==
               [title1, title2] |> Enum.sort()
    end
  end

  describe "UpdateTask" do
    setup do
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      {:ok, task, [%StateModification{value: tasks}]} =
        Tasks.CreateTask.run(%{title: "Original Title", deadline: deadline}, %{
          state: %{tasks: %{}}
        })

      %{task_id: task.id, task: task, tasks: tasks}
    end

    test "updates an existing task", %{task_id: task_id, tasks: tasks} do
      new_title = "Updated Title"
      new_deadline = DateTime.utc_now() |> DateTime.add(7200, :second)

      assert {:ok, updated_task, [%StateModification{} = directive]} =
               Tasks.UpdateTask.run(
                 %{id: task_id, title: new_title, deadline: new_deadline},
                 %{state: %{tasks: tasks}}
               )

      assert %Task{
               id: ^task_id,
               title: ^new_title,
               completed: false,
               created_at: created_at,
               deadline: ^new_deadline
             } = updated_task

      assert DateTime.diff(created_at, DateTime.utc_now()) < 1

      # Verify directive
      assert directive.op == :set
      assert directive.path == [:tasks]
      assert map_size(directive.value) == 1
      assert directive.value[task_id] == updated_task
    end

    test "returns error when task not found", %{tasks: tasks} do
      assert {:error, :task_not_found} =
               Tasks.UpdateTask.run(
                 %{id: "non-existent-id", title: "New Title", deadline: DateTime.utc_now()},
                 %{state: %{tasks: tasks}}
               )
    end
  end

  describe "ToggleTask" do
    setup do
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      {:ok, task, [%StateModification{value: tasks}]} =
        Tasks.CreateTask.run(%{title: "Test Task", deadline: deadline}, %{state: %{tasks: %{}}})

      %{task_id: task.id, task: task, tasks: tasks}
    end

    test "toggles task completion status", %{task_id: task_id, tasks: tasks} do
      assert {:ok, updated_task, [%StateModification{} = directive]} =
               Tasks.ToggleTask.run(%{id: task_id}, %{state: %{tasks: tasks}})

      assert %Task{
               id: ^task_id,
               title: "Test Task",
               completed: true,
               created_at: created_at,
               deadline: deadline
             } = updated_task

      assert DateTime.diff(created_at, DateTime.utc_now()) < 1

      # Verify directive
      assert directive.op == :set
      assert directive.path == [:tasks]
      assert map_size(directive.value) == 1
      assert directive.value[task_id] == updated_task

      # Toggle back
      assert {:ok, final_task, [%StateModification{value: final_tasks}]} =
               Tasks.ToggleTask.run(%{id: task_id}, %{state: %{tasks: directive.value}})

      assert %Task{
               id: ^task_id,
               title: "Test Task",
               completed: false,
               created_at: ^created_at,
               deadline: ^deadline
             } = final_task

      assert map_size(final_tasks) == 1
      assert final_tasks[task_id] == final_task
    end

    test "returns error when task not found", %{tasks: tasks} do
      assert {:error, :task_not_found} =
               Tasks.ToggleTask.run(%{id: "non-existent-id"}, %{state: %{tasks: tasks}})
    end
  end

  describe "DeleteTask" do
    setup do
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      {:ok, task, [%StateModification{value: tasks}]} =
        Tasks.CreateTask.run(%{title: "Test Task", deadline: deadline}, %{state: %{tasks: %{}}})

      %{task_id: task.id, task: task, tasks: tasks}
    end

    test "deletes an existing task", %{task_id: task_id, task: task, tasks: tasks} do
      assert {:ok, ^task, [%StateModification{} = directive]} =
               Tasks.DeleteTask.run(%{id: task_id}, %{state: %{tasks: tasks}})

      # Verify directive
      assert directive.op == :set
      assert directive.path == [:tasks]
      assert map_size(directive.value) == 0
      assert is_nil(directive.value[task_id])
    end

    test "returns error when task not found", %{tasks: tasks} do
      assert {:error, :task_not_found} =
               Tasks.DeleteTask.run(%{id: "non-existent-id"}, %{state: %{tasks: tasks}})
    end
  end

  describe "Task struct" do
    test "creates a valid task with new/1" do
      title = "Test Task"
      deadline = DateTime.utc_now() |> DateTime.add(3600, :second)

      task = Task.new(title, deadline)

      assert %Task{
               id: id,
               title: ^title,
               completed: false,
               created_at: created_at,
               deadline: ^deadline
             } = task

      assert is_binary(id)
      assert DateTime.diff(created_at, DateTime.utc_now()) < 1
    end
  end
end
