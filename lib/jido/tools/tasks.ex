defmodule Jido.Tools.Tasks.Task do
  @moduledoc """
  Represents a task within the Jido task management system.

  This struct defines the structure and behavior of tasks that can be
  managed by agents through task-related actions.
  """

  @enforce_keys [:id, :title]
  defstruct [
    :id,
    :title,
    :deadline,
    completed: false,
    created_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          deadline: DateTime.t() | nil,
          completed: boolean(),
          created_at: DateTime.t()
        }

  @doc """
  Creates a new task with the given title and optional deadline.
  """
  @spec new(String.t(), DateTime.t() | nil) :: t()
  def new(title, deadline \\ nil) do
    %__MODULE__{
      id: Jido.Util.generate_id(),
      title: title,
      completed: false,
      created_at: DateTime.utc_now(),
      deadline: deadline
    }
  end
end

defmodule Jido.Tools.Tasks.Create do
  @moduledoc """
  Action for creating a new task.

  Creates a task with the specified title and optional deadline,
  adding it to the agent's state.
  """

  use Jido.Action,
    name: "task_create",
    description: "Create a new task",
    schema: [
      title: [type: :string, required: true],
      deadline: [type: :any, required: false]
    ]

  alias Jido.Tools.Tasks.Task
  alias Jido.Agent.Directive.StateModification

  @spec run(map(), map()) :: {:ok, map()} | {:ok, map(), any()} | {:error, any()}
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

defmodule Jido.Tools.Tasks.Update do
  @moduledoc """
  Action for updating an existing task.

  Updates a task's properties such as title and deadline based on the
  provided task ID.
  """

  use Jido.Action,
    name: "task_update",
    description: "Update an existing task",
    schema: [
      id: [type: :string, required: true],
      title: [type: :string, required: false],
      deadline: [type: :any, required: false]
    ]

  alias Jido.Tools.Tasks.Task
  alias Jido.Agent.Directive.StateModification

  @impl true
  def run(params, context) do
    case get_task(params.id, context.state) do
      nil ->
        {:error, :task_not_found}

      task ->
        updated_task = %Task{
          task
          | title: Map.get(params, :title, task.title),
            deadline: Map.get(params, :deadline, task.deadline)
        }

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

defmodule Jido.Tools.Tasks.Toggle do
  @moduledoc """
  Action for toggling the completion status of a task.

  Switches a task's completed status between true and false based on
  the provided task ID.
  """

  use Jido.Action,
    name: "task_toggle",
    description: "Toggle the completion status of a task",
    schema: [
      id: [type: :string, required: true]
    ]

  alias Jido.Tools.Tasks.Task
  alias Jido.Agent.Directive.StateModification

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

defmodule Jido.Tools.Tasks.Delete do
  @moduledoc """
  Action for deleting a task.

  Removes a task from the agent's state based on the provided task ID.
  """

  use Jido.Action,
    name: "task_delete",
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
