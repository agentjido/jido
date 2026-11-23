defmodule Jido.Examples.DistributedAgents.TicketResult do
  @moduledoc "Looks up a terminal ticket result by Address and Turn ID after the host changes."

  alias Jido.Agent.Address
  @doc "Returns the retained Turn status and identifiers for the ticket."
  def lookup(instance, %Address{} = address, turn_id) do
    with {:ok, result} <- Jido.turn_result(instance, address, turn_id) do
      {:ok, Map.take(result, [:status, :agent_address, :agent_activation_id, :agent_revision, :turn_id])}
    end
  end
end
