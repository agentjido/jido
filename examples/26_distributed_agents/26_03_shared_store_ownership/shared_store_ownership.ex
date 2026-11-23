defmodule Jido.Examples.DistributedAgents.SharedStoreOwnership do
  @moduledoc "Attempts local activation on a selected host to demonstrate the current ownership boundary."

  alias Jido.Agent.Address

  @doc "Asks one host to restore the Agent from its persistence store."
  def activate({host, instance}, %Address{} = address) do
    :erpc.call(host, Jido, :activate_agent, [instance, address], 6_000)
  end
end
