defmodule Jido.Examples.DistributedAgents.PartitionedIngress do
  @moduledoc "Shows what happens when both ingress nodes route a ticket to their local instance."

  alias Jido.Agent.Address
  alias Jido.Examples.DistributedAgents.Ticket

  @doc "Uses the local namespace to handle an incoming ticket note."
  def record_note(instance, %Address{} = address, note) do
    Jido.call(instance, address, Ticket.note(note))
  end
end
