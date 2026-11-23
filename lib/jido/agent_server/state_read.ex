defmodule Jido.AgentServer.StateRead do
  @moduledoc false

  alias Jido.Agent

  @ecto_state_provider Jido.Plugin.EctoState

  def fetch(%Agent{plugins: plugins, id: id, state: state}) do
    case Enum.find(plugins, &(&1.provider == @ecto_state_provider)) do
      %{data: %{schema: schema}} -> fetch_ecto(schema, id)
      nil -> {:ok, state}
    end
  end

  defp fetch_ecto(schema, id) do
    repo = schema.repo()

    case repo.get(schema, id) do
      nil -> {:error, :ecto_state_not_found}
      row -> {:ok, row}
    end
  catch
    kind, _reason when kind in [:error, :exit] -> {:error, :ecto_state_unavailable}
  end
end
