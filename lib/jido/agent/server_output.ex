defmodule Jido.Agent.Server.Output do
  use ExDbug, enabled: false
  alias Jido.Signal
  alias Jido.Signal.Dispatch

  @default_dispatch {:logger, []}

  def emit(signal, opts \\ [])

  def emit(nil, _opts) do
    dbug("No signal provided")
    {:error, :no_signal}
  end

  def emit(%Signal{} = signal, opts) do
    # First update correlation and causation IDs only if provided
    signal = %{
      signal
      | jido_correlation_id: Keyword.get(opts, :correlation_id) || signal.jido_correlation_id,
        jido_causation_id: Keyword.get(opts, :causation_id) || signal.jido_causation_id
    }

    # Then handle dispatch config and dispatch
    dispatch_config =
      Keyword.get(opts, :dispatch) || signal.jido_dispatch || @default_dispatch

    dbug("Emitting", signal: signal, opts: opts)
    dbug("Using dispatch config", dispatch_config: dispatch_config)

    Dispatch.dispatch(signal, dispatch_config)
  end

  def emit(invalid, _opts) do
    dbug("Invalid signal provided", signal: invalid)
    {:error, :invalid_signal}
  end
end
