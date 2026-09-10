defmodule Jido.Agent.Plugin.Reduction do
  @moduledoc """
  Read-only input for one pure Agent Plugin state reduction.

  A reducer can inspect the complete state before the Turn, the current
  candidate state, its pure prepared input, and all validated Directives. It
  returns only the next value for its declared Plugin state field.
  """

  @enforce_keys [
    :plugin,
    :agent_id,
    :agent_module,
    :signal,
    :state_before,
    :state,
    :plugin_state,
    :prepared_input,
    :directives
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plugin: module(),
          agent_id: String.t(),
          agent_module: module(),
          signal: Jido.Signal.t(),
          state_before: map(),
          state: map(),
          plugin_state: term(),
          prepared_input: term(),
          directives: [struct()]
        }
end
