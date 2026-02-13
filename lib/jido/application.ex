defmodule Jido.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    Jido.Telemetry.setup()

    children = []

    register_signal_extensions()
    Jido.Discovery.init_async()

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end

  # Ensure critical signal extensions are registered
  defp register_signal_extensions do
    extensions = [
      Jido.Signal.Ext.Trace,
      Jido.Signal.Ext.Dispatch,
      Jido.Signal.Ext.Target
    ]

    for ext <- extensions do
      Code.ensure_loaded(ext)
      Jido.Signal.Ext.Registry.register(ext)
    end

    :ok
  rescue
    # Gracefully handle missing modules during compilation or testing
    _ -> :ok
  end
end
