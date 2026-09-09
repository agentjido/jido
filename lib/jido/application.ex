defmodule Jido.Application do
  @moduledoc false
  use Application

  @doc false
  def start(_type, _args) do
    Jido.Telemetry.setup()

    Supervisor.start_link(
      [Jido.Instance.NamespaceRegistry],
      strategy: :one_for_one,
      name: Jido.Supervisor
    )
  end
end
