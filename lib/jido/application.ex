defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Workflow Async Actions Task Supervisor
      {Task.Supervisor, name: Jido.Workflow.TaskSupervisor},

      # Default global process registry
      {Registry, keys: :unique, name: Jido.Registry},

      # Agent Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.Agent.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Agent.Supervisor},

      # Bus Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.Bus.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.Bus.Supervisor},

      # Default Bus - register with a name
      {Jido.Signal.Bus, name: :default_bus},

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
