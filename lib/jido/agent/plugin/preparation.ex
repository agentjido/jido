defmodule Jido.Agent.Plugin.Preparation do
  @moduledoc """
  Read-only input for one pure Agent Plugin preparation callback.

  A callback can inspect the source Signal, Agent identity, complete Agent
  state, its owned state, and all ordered routes that match the Signal. It
  returns one package-owned value. The contract has no return path for a
  replacement Signal, caller context, route, or Agent.
  """

  @enforce_keys [
    :plugin,
    :agent_id,
    :agent_module,
    :agent_state,
    :signal,
    :plugin_state,
    :route_candidates
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plugin: module(),
          agent_id: String.t(),
          agent_module: module(),
          agent_state: map(),
          signal: Jido.Signal.t(),
          plugin_state: term(),
          route_candidates: [map()]
        }
end
