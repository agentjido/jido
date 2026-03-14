defmodule Jido.AgentServer.Lifecycle.Noop do
  @moduledoc """
  Default no-op lifecycle implementation.
  Used when no lifecycle management is needed.
  """
  @behaviour Jido.AgentServer.Lifecycle

  @impl true
  def init(_opts, state), do: state

  @impl true
  def handle_event(_event, state), do: {:cont, state}

  @impl true
  def persist_cron_specs(_state, _cron_specs), do: :ok

  @impl true
  def terminate(_reason, _state), do: :ok
end
