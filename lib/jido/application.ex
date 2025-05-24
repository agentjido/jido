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

    # Initialize discovery cache asynchronously
    Task.start(fn ->
      :ok = Jido.Discovery.init()
    end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
