defmodule Jido.Skills.Tasks do
  @moduledoc """
  An example skill that provides task management capabilities to agents.

  This skill registers task-related actions (create, update, toggle, delete)
  with the agent and handles task-related signals.
  """

  use Jido.Skill,
    name: "task_skill",
    description: "A skill to let agents manage a list of tasks",
    opts_key: :tasks,
    signal_patterns: [
      "jido.cmd.task.*",
      "jido.event.task.*"
    ],
    actions: [
      Jido.Tools.Tasks.Create,
      Jido.Tools.Tasks.Update,
      Jido.Tools.Tasks.Toggle,
      Jido.Tools.Tasks.Delete
    ]

  require Logger

  alias Jido.Instruction

  @impl true
  @spec router(keyword()) :: [Jido.Signal.Router.Route.t()]
  def router(_opts) do
    [
      %Jido.Signal.Router.Route{
        path: "jido.cmd.task.create",
        target: %Instruction{action: Jido.Tools.Tasks.Create},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.cmd.task.update",
        target: %Instruction{action: Jido.Tools.Tasks.Update},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.cmd.task.toggle",
        target: %Instruction{action: Jido.Tools.Tasks.Toggle},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.cmd.task.delete",
        target: %Instruction{action: Jido.Tools.Tasks.Delete},
        priority: 0
      }
    ]
  end

  @impl true
  @spec handle_signal(Jido.Signal.t(), Jido.Skill.t()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def handle_signal(%Jido.Signal{} = signal, _skill) do
    {:ok, signal}
  end

  @impl true
  @spec transform_result(Jido.Signal.t(), term(), Jido.Skill.t()) ::
          {:ok, term()} | {:error, any()}
  def transform_result(_signal, result, _skill) do
    {:ok, result}
  end
end
