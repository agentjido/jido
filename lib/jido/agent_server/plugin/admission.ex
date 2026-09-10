defmodule Jido.AgentServer.Plugin.Admission do
  @moduledoc """
  Read-only input for one live Agent Server Plugin admission callback.

  Admission can inspect live command data and its own pure prepared input. It
  can reject the Turn or return one transient runtime input. It has no return
  path for a replacement Agent, Signal, caller context, or prepared input.
  """

  @enforce_keys [
    :plugin,
    :agent_id,
    :agent_module,
    :signal,
    :caller_context,
    :plugin_state,
    :prepared_input,
    :state_version
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plugin: module(),
          agent_id: String.t(),
          agent_module: module(),
          signal: Jido.Signal.t(),
          caller_context: map(),
          plugin_state: term(),
          prepared_input: term(),
          state_version: non_neg_integer()
        }
end
