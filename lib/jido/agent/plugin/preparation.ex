defmodule Jido.Agent.Plugin.Preparation do
  @moduledoc """
  Read-only input for one pure Agent Plugin preparation callback.

  A callback can inspect the source Signal, Agent identity, and its owned state.
  It returns one package-owned value. The contract has no return path for a
  replacement Signal, caller context, route, or Agent.
  """

  @enforce_keys [:plugin, :agent_id, :agent_module, :signal, :plugin_state]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plugin: module(),
          agent_id: String.t(),
          agent_module: module(),
          signal: Jido.Signal.t(),
          plugin_state: term()
        }
end
