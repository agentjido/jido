defmodule Jido.Plugin.Context.Commit do
  @moduledoc """
  Read-only view for one Plugin commit callback.

  For `before_commit/3`, the values describe the validated proposal and its
  next state version. That callback also receives the Plugin's transient
  admission input. For `after_commit/3`, the values describe the completed
  commit and `runtime_input` is nil.
  `jido_persistence?` reports whether Jido stores its own checkpoints.

  Startup and restore use `Jido.Plugin.Init`, not this notification.
  """

  @enforce_keys [:plugin, :turn_id, :agent_id, :agent_module, :plugin_state, :state_version]
  defstruct @enforce_keys ++ [jido: nil, partition: nil, runtime_input: nil, jido_persistence?: false]

  @typedoc "Read-only context for one Plugin commit callback."
  @type t :: %__MODULE__{
          plugin: module(),
          turn_id: String.t(),
          agent_id: String.t(),
          agent_module: module(),
          plugin_state: term(),
          state_version: non_neg_integer(),
          jido: atom() | nil,
          partition: term(),
          runtime_input: term(),
          jido_persistence?: boolean()
        }
end
