defmodule Jido.Actions.Tasks do
  @moduledoc """
  Provides a set of actions for managing tasks within an agent.

  This module implements the Jido.Action behavior and offers a collection
  of actions for creating, updating, toggling, and deleting tasks.
  """

  use Jido.Action,
    name: "tasks",
    description: "Actions for managing a list of tasks"

  alias Jido.Agent.Directive.StateModification
  alias Jido.Signal.ID

  defmodule Task do
    @moduledoc """
    Defines the task data structure used by the Tasks actions.

    Represents a task with properties such as id, title, completion status,
    creation timestamp, and deadline.
    """

    use TypedStruct

    typedstruct do
      field(:id, :string)
      field(:title, :string)
      field(:completed, :boolean)
      field(:created_at, :any)
      field(:deadline, :any)
    end

    def new(title, deadline) do
      {id, _timestamp} = ID.generate()

      %__MODULE__{
        id: id,
        title: title,
        completed: false,
        created_at: DateTime.utc_now(),
        deadline: deadline
      }
    end
  end

  defmodule CreateTask do
    @moduledoc """
    Action for creating a new task.

    Creates a task with the specified title and optional deadline,
    adding it to the agent's state.
    """

    use Jido.Action,
      name: "create",
      description: "Create a new task",
      schema: [
        title: [type: :string, required: true],
        deadline: [type: :any, required: false]
      ]

    alias Jido.Actions.Tasks.Task

    @impl true
    def run(params, context) do
      task = Task.new(params.title, params.deadline)
      tasks = Map.get(context.state, :tasks, %{})
      updated_tasks = Map.put(tasks, task.id, task)

      {:ok, task,
       [
         %StateModification{
           op: :set,
           path: [:tasks],
           value: updated_tasks
         }
       ]}
    end
  end

  defmodule UpdateTask do
    @moduledoc """
    Action for updating an existing task.

    Updates a task's properties such as title and deadline based on the
    provided task ID.
    """

    use Jido.Action,
      name: "update",
      description: "Update an existing task",
      schema: [
        id: [type: :string, required: true],
        title: [type: :string, required: false],
        deadline: [type: :any, required: false]
      ]

    alias Jido.Actions.Tasks.Task

    @impl true
    def run(params, context) do
      case get_task(params.id, context.state) do
        nil ->
          {:error, :task_not_found}

        task ->
          updated_task = %Task{task | title: params.title, deadline: params.deadline}

          tasks = Map.get(context.state, :tasks, %{})
          updated_tasks = Map.put(tasks, params.id, updated_task)

          {:ok, updated_task,
           [
             %StateModification{
               op: :set,
               path: [:tasks],
               value: updated_tasks
             }
           ]}
      end
    end

    defp get_task(id, state) do
      state
      |> Map.get(:tasks, %{})
      |> Map.get(id)
    end
  end

  defmodule ToggleTask do
    @moduledoc """
    Action for toggling the completion status of a task.

    Switches a task's completed status between true and false based on
    the provided task ID.
    """

    use Jido.Action,
      name: "toggle",
      description: "Toggle the completion status of a task",
      schema: [
        id: [type: :string, required: true]
      ]

    alias Jido.Actions.Tasks.Task

    @impl true
    def run(params, context) do
      case get_task(params.id, context.state) do
        nil ->
          {:error, :task_not_found}

        task ->
          updated_task = %Task{task | completed: !task.completed}
          tasks = Map.get(context.state, :tasks, %{})
          updated_tasks = Map.put(tasks, params.id, updated_task)

          {:ok, updated_task,
           [
             %StateModification{
               op: :set,
               path: [:tasks],
               value: updated_tasks
             }
           ]}
      end
    end

    defp get_task(id, state) do
      state
      |> Map.get(:tasks, %{})
      |> Map.get(id)
    end
  end

  defmodule DeleteTask do
    @moduledoc """
    Action for deleting a task.

    Removes a task from the agent's state based on the provided task ID.
    """

    use Jido.Action,
      name: "delete",
      description: "Delete a task",
      schema: [
        id: [type: :string, required: true]
      ]

    alias Jido.Agent.Directive.StateModification

    @impl true
    def run(params, context) do
      case get_task(params.id, context.state) do
        nil ->
          {:error, :task_not_found}

        task ->
          tasks = Map.get(context.state, :tasks, %{})
          updated_tasks = Map.delete(tasks, params.id)

          {:ok, task,
           [
             %StateModification{
               op: :set,
               path: [:tasks],
               value: updated_tasks
             }
           ]}
      end
    end

    defp get_task(id, state) do
      state
      |> Map.get(:tasks, %{})
      |> Map.get(id)
    end
  end
end
