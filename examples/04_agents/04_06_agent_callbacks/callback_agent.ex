defmodule Jido.Examples.CallbackAgent do
  @moduledoc "Uses the public initialize, checkpoint, and restore callbacks."

  use Jido.Agent, name: "agent_callback_example", vsn: 2

  state do
    schema(
      Jido.Joi.object(%{
        count: Jido.Joi.integer(),
        initialized_for: Jido.Joi.string()
      })
    )

    initial_state %{count: 0}
  end

  @impl Jido.Agent
  def initialize(state, %{id: id}) do
    {:ok, Map.put(state, :initialized_for, id)}
  end

  @impl Jido.Agent
  def checkpoint(agent, _context) do
    {:ok, %{id: agent.id, count: agent.state.count}}
  end

  @impl Jido.Agent
  def restore(%{id: id, count: count}, _context) do
    instantiate(id: id, state: %{count: count})
  end
end
