defmodule Jido.AgentServer.StateRead do
  @moduledoc false

  alias Jido.Agent.StateSource
  alias Jido.AgentServer.Snapshot

  def populate(%Snapshot{agent: agent} = snapshot) do
    case StateSource.ecto_schema(agent) do
      nil ->
        snapshot

      schema ->
        with {:ok, row} <- fetch_row(schema, agent.id) do
          %{snapshot | agent: %{agent | state: StateSource.observe(agent, row)}}
        end
    end
  end

  defp fetch_row(schema, id) do
    repo = schema.repo()

    case repo.get(schema, id) do
      nil -> {:error, :ecto_state_not_found}
      row -> {:ok, row}
    end
  catch
    kind, _reason when kind in [:error, :exit] -> {:error, :ecto_state_unavailable}
  end
end
