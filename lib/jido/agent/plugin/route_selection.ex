defmodule Jido.Agent.Plugin.RouteSelection do
  @moduledoc """
  Read-only input for one pure Agent Plugin route selection callback.

  The callback can select only one alias from `candidates`, use `:default`, or
  reject the Turn. It cannot return an executable, Signal, Agent state, or
  Directive.
  """

  @enforce_keys [
    :plugin,
    :agent_id,
    :agent_module,
    :agent_state,
    :plugin_state,
    :signal,
    :prepared_input,
    :candidates
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plugin: module(),
          agent_id: String.t(),
          agent_module: module() | nil,
          agent_state: map(),
          plugin_state: term(),
          signal: Jido.Signal.t(),
          prepared_input: term(),
          candidates: [map()]
        }
end
