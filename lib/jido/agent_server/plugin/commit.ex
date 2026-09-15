defmodule Jido.AgentServer.Plugin.Commit do
  @moduledoc """
  Read-only committed view for one Agent Server Plugin notification.

  `plugin_state` and `state_version` describe the same completed Turn commit.
  The view contains only the selected Plugin-owned field and identity context.
  It contains no complete Agent, runtime handle, storage adapter, caller
  context, or callback return path for changing committed state.

  Startup and restore use `Jido.Plugin.Init`, not this notification.
  """

  @enforce_keys [:plugin, :turn_id, :agent_id, :agent_module, :plugin_state, :state_version]
  defstruct @enforce_keys ++ [jido: nil, partition: nil]

  @type t :: %__MODULE__{
          plugin: module(),
          turn_id: String.t(),
          agent_id: String.t(),
          agent_module: module(),
          plugin_state: term(),
          state_version: non_neg_integer(),
          jido: atom() | nil,
          partition: term()
        }
end
