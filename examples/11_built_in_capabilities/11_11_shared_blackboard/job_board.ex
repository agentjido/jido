defmodule Jido.Examples.SharedBlackboard.JobBoard do
  @moduledoc "Gives each inventory job its own board and owner Agent."

  alias Jido.Agent
  alias Jido.Plugin.Blackboard.Server

  use Jido.Agent, name: "inventory_job_board"

  def definition(name, persistence) do
    Agent.define!(%{
      name: "inventory_job_board",
      module: __MODULE__,
      plugins: [
        %{
          id: Server.id(),
          provider: Server,
          vsn: Server.vsn(),
          data: %{name: name, initial: %{"bin-a" => 0}, persistence: persistence}
        }
      ]
    })
  end

  def create(instance, name) do
    with {:ok, address} <- Jido.agent_address(instance, "inventory-job/" <> name) do
      Jido.create_agent(instance, address, definition(name, :inherit))
    end
  end
end
