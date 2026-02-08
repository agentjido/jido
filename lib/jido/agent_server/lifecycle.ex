defmodule Jido.AgentServer.Lifecycle do
  @moduledoc """
  Internal behavior for AgentServer lifecycle hooks.

  Allows instance managers and other orchestrators to inject
  attachment tracking, idle timeouts, and storage coordination
  without polluting the core runtime.
  """

  @type state :: map()
  @type event :: :attach | :detach | :touch | :idle_timeout | {:down, reference(), pid()}

  @callback init(lifecycle :: term(), server_state :: map()) :: map()
  @callback handle_event(event :: term(), server_state :: map()) ::
              {:cont, map()} | {:stop, reason :: term(), map()}
  @callback terminate(reason :: term(), server_state :: map()) :: :ok

  @optional_callbacks [init: 2, handle_event: 2, terminate: 2]
end
