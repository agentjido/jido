defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Workflow Async Actions Task Supervisor
      {Task.Supervisor, name: Jido.Workflow.TaskSupervisor},

      # Default PubSub
      {Phoenix.PubSub, name: Jido.PubSub},

      # Agent Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.AgentRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor},

      # Bus Registry & Default Supervisor
      {Registry, keys: :unique, name: Jido.BusRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Jido.BusSupervisor}

      # Default Agent Server
      # BasicServer
    ]

    # Initialize discovery cache asynchronously
    Task.start(fn ->
      :ok = Jido.Discovery.init()
    end)

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
