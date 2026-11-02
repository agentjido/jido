defmodule Jido.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Jido.Signal.Registry},
      Jido.Discovery
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
  end
end
