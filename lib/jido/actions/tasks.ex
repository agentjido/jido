defmodule Jido.Actions.Tasks do
  use Jido.Action,
    name: "tasks",
    description: "Actions for managing a list of tasks"

  alias Jido.Agent.Directive.StateModification
  alias Jido.Signal.ID

  defmodule Task do
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
    use Jido.Action,
      name: "create",
      description: "Create a new task",
      schema: [
        title: [type: :string, required: true],
        deadline: [type: :any, required: true]
      ]

    alias Jido.Actions.Tasks.Task

    @impl true
    def run(params, context) do
      task = Task.new(params.title, params.deadline)
      tasks = Map.get(context.state, :tasks, %{})
      updated_tasks = Map.put(tasks, task.id, task)

      {:ok, task, [%StateModification{
        op: :set,
        path: [:tasks],
        value: updated_tasks
      }]}
    end
  end

  defmodule UpdateTask do
    use Jido.Action,
      name: "update",
      description: "Update a task's title and deadline",
      schema: [
        id: [type: :string, required: true],
        title: [type: :string, required: true],
        deadline: [type: :any, required: true]
      ]

    alias Jido.Actions.Tasks.Task

    @impl true
    def run(params, context) do
      case get_task(params.id, context.state) do
        nil ->
          {:error, :task_not_found}

        task ->
          updated_task = %Task{task |
            title: params.title,
            deadline: params.deadline
          }

          tasks = Map.get(context.state, :tasks, %{})
          updated_tasks = Map.put(tasks, params.id, updated_task)

          {:ok, updated_task, [%StateModification{
            op: :set,
            path: [:tasks],
            value: updated_tasks
          }]}
      end
    end

    defp get_task(id, state) do
      state
      |> Map.get(:tasks, %{})
      |> Map.get(id)
    end
  end

  defmodule ToggleTask do
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

          {:ok, updated_task, [%StateModification{
            op: :set,
            path: [:tasks],
            value: updated_tasks
          }]}
      end
    end

    defp get_task(id, state) do
      state
      |> Map.get(:tasks, %{})
      |> Map.get(id)
    end
  end

  defmodule DeleteTask do
    use Jido.Action,
      name: "delete",
      description: "Delete an existing task",
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

          {:ok, task, [%StateModification{
            op: :set,
            path: [:tasks],
            value: updated_tasks
          }]}
      end
    end

    defp get_task(id, state) do
      state
      |> Map.get(:tasks, %{})
      |> Map.get(id)
    end
  end
end
