defmodule Jido.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    Jido.Telemetry.setup()

    children = [
      Jido.Storage.ETS.Owner
    ]

    Jido.Discovery.init_async()

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
