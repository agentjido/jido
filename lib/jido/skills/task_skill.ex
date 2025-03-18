defmodule Jido.Examples.TaskSkill do
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
    ]

  require Logger

  def mount(agent, _opts) do
    actions = [CreateTask, UpdateTask, ToggleTask, DeleteTask]

    # Register the actions with the agent
    Jido.Agent.register_action(agent, actions)
  end

  def run(input) do
    {:ok, %{input: input, result: "Hello, World!"}}
  end

  def router(_opts) do
    [
      {"jido.cmd.task.create", %Instruction{action: CreateTask}},
      {"jido.cmd.task.update", %Instruction{action: UpdateTask}},
      {"jido.cmd.task.toggle", %Instruction{action: ToggleTask}},
      {"jido.cmd.task.delete", %Instruction{action: DeleteTask}}
    ]
  end
end
