defmodule Jido.Planner do
  @moduledoc """
  A behavior for planning sequences of actions based on the Agent state.
  """

  @doc """
  Plans a sequence of actions for the given agent, command, and input data.

  ## Parameters
    * `agent` - The agent struct containing current state
    * `command` - The Action module to execute or planning command
    * `params` - Map of parameters for the Action or planning

  ## Returns
    * `{:ok, actions}` - Successfully created plan of actions
    * `{:error, reason}` - Planning failed
  """
  @type action :: module() | {module(), map()}
  @callback plan(agent :: struct(), command :: module() | atom(), params :: map()) ::
              {:ok, [action()]} | {:error, any()}
end
