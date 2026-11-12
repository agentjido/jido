defmodule Jido.AgentServer.PluginSupervisor do
  @moduledoc false

  use Supervisor

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok)

  @impl true
  def init(:ok) do
    Supervisor.init([], strategy: :one_for_one, max_restarts: 0, max_seconds: 1)
  end
end
