defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Telemetry handler
      Jido.Telemetry,

      # Exec Async Actions Task Supervisor
      {Task.Supervisor, name: Jido.TaskSupervisor},

      # Global Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Agent.Supervisor},

      # Add the Jido Scheduler (Quantum) under the name :jido_quantum
      {Jido.Scheduler, name: Jido.Quantum}
    ]

    # Register essential signal extensions that may not have been auto-registered
    register_signal_extensions()

    # Initialize discovery cache asynchronously
    Task.start(fn ->
      :ok = Jido.Discovery.init()
    end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end

  # Ensure critical signal extensions are registered
  defp register_signal_extensions do
    # Register the Trace extension from jido_signal
    Code.ensure_loaded(Jido.Signal.Ext.Trace)
    Jido.Signal.Ext.Registry.register(Jido.Signal.Ext.Trace)

    # Register the Dispatch extension from jido_signal if available
    Code.ensure_loaded(Jido.Signal.Ext.Dispatch)
    Jido.Signal.Ext.Registry.register(Jido.Signal.Ext.Dispatch)

    # Register the Target extension from jido
    Code.ensure_loaded(Jido.Signal.Ext.Target)
    Jido.Signal.Ext.Registry.register(Jido.Signal.Ext.Target)
  end
end
