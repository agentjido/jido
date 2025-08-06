defmodule Jido.Skills.StateManager do
  @moduledoc """
  A skill that provides state management capabilities for agents.

  This skill allows agents to get, set, update, and delete values in their state
  using structured signals.

  ## Signal Types

  - `jido.state.get` - Get a value from the agent's state
  - `jido.state.set` - Set a value in the agent's state
  - `jido.state.update` - Update a value in the agent's state
  - `jido.state.delete` - Delete a value from the agent's state
  """

  alias Jido.Instruction

  use Jido.Skill,
    name: "state_manager_skill",
    description: "Provides state management capabilities for agents",
    category: "Core",
    tags: ["state", "management", "storage"],
    vsn: "0.1.0",
    opts_key: :state_manager,
    opts_schema: [],
    signal_patterns: [
      "jido.state.**"
    ]

  def mount(agent, _opts) do
    {:ok, agent}
  end

  def router(_opts \\ []) do
    [
      {"jido.state.get", %Instruction{action: Jido.Actions.StateManager.Get}},
      {"jido.state.set", %Instruction{action: Jido.Actions.StateManager.Set}},
      {"jido.state.update", %Instruction{action: Jido.Actions.StateManager.Update}},
      {"jido.state.delete", %Instruction{action: Jido.Actions.StateManager.Delete}}
    ]
  end

  def handle_signal(signal, _skill_opts) do
    {:ok, signal}
  end
end
