defmodule Jido.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    Jido.Telemetry.attach_default_handler()

    Supervisor.start_link(
      [
        Jido.Instance.NamespaceRegistry,
        Jido.Persistence.ETS.Owner,
        {Runic.Runner, name: Jido.exec_runner_name(nil), store: Jido.AgentServer.Store},
        {Jido.Discovery, []}
      ],
      strategy: :one_for_one,
      name: Jido.Supervisor
    )
  end
end
