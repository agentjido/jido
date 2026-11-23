defmodule Jido.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    Jido.Telemetry.attach_default_handler()

    children = [
      {Registry, keys: :unique, name: Jido.Signal.Registry},
      {Registry, keys: :unique, name: Jido.Blackboard.Registry},
      {Task.Supervisor, name: Jido.Exec.TaskSupervisor, max_children: Application.get_env(:jido, :max_exec_runs, 64)},
      Jido.Catalog.Discovery,
      Jido.Telemetry.AI.CorrelationStore,
      Jido.Instance.NamespaceRegistry,
      Jido.Persistence.ETS.Owner,
      {Runic.Runner, name: Jido.Instance.Names.exec_runner(nil), store: Jido.Persistence.ContinuationStore}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor) do
      {:ok, supervisor} ->
        Jido.Telemetry.AI.attach_default_handlers()
        {:ok, supervisor}

      other ->
        other
    end
  end
end
