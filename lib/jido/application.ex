defmodule Jido.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    Jido.Telemetry.attach_default_handler()

    children = [
      {Registry, keys: :unique, name: Jido.Signal.Registry},
      {Task.Supervisor, name: Jido.Exec.TaskSupervisor, max_children: :infinity},
      Jido.Discovery,
      Jido.AI.Telemetry.CorrelationStore,
      Jido.Instance.NamespaceRegistry,
      Jido.Persistence.ETS.Owner,
      {Runic.Runner, name: Jido.exec_runner_name(nil), store: Jido.AgentServer.Store}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor) do
      {:ok, supervisor} ->
        Jido.AI.Telemetry.attach_default_handlers()
        {:ok, supervisor}

      other ->
        other
    end
  end
end
