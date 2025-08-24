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
    ],
    actions: [
      Jido.Tools.StateManager.Get,
      Jido.Tools.StateManager.Set,
      Jido.Tools.StateManager.Update,
      Jido.Tools.StateManager.Delete
    ]

  def mount(agent, _opts) do
    {:ok, agent}
  end

  def router(_opts \\ []) do
    [
      %Jido.Signal.Router.Route{
        path: "jido.state.get",
        target: %Instruction{action: Jido.Tools.StateManager.Get},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.state.set",
        target: %Instruction{action: Jido.Tools.StateManager.Set},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.state.update",
        target: %Instruction{action: Jido.Tools.StateManager.Update},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "jido.state.delete",
        target: %Instruction{action: Jido.Tools.StateManager.Delete},
        priority: 0
      }
    ]
  end

  def handle_signal(signal, _skill_opts) do
    {:ok, signal}
  end
end
