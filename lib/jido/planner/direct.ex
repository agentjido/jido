defmodule Jido.Planner.Direct do
  @moduledoc """
  Default planner that creates a simple single-action plan.
  Supports both single actions and lists of actions.
  """

  @behaviour Jido.Planner

  @impl true
  def plan(_agent, action, params) when is_atom(action) do
    {:ok, [{action, params}]}
  end

  def plan(_agent, actions, _params) when is_list(actions) do
    {:ok, actions}
  end

  def plan(_agent, command, _params) do
    {:error, "Invalid command: #{inspect(command)}. Expected an Action module or :actions."}
  end
end
