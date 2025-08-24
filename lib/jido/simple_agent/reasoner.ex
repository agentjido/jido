defmodule Jido.SimpleAgent.Reasoner do
  @moduledoc """
  Behavior for SimpleAgent reasoners.

  A reasoner takes the current message and agent state and decides what action to take:
  - Return a direct response
  - Call a tool/action
  - Handle errors
  """

  @doc """
  Analyzes the current message and state to determine the next action.

  Returns:
  - `{:respond, message}` - Return a direct response to the user
  - `{:tool_call, action_module, params}` - Execute a tool with parameters
  - `{:error, reason}` - Handle reasoning errors
  """
  @callback reason(message :: map() | nil, state :: map()) ::
              {:respond, String.t()}
              | {:tool_call, module(), map()}
              | {:error, term()}
end
