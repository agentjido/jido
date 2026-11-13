defmodule Jido.Examples.StableAddresses do
  @moduledoc "Builds and serializes public stable Agent addresses."

  alias Jido.Agent.Address

  def build(instance, id, partition), do: Jido.agent_address(instance, id, partition: partition)
  def encode(%Address{} = address), do: Address.to_map(address)
  def decode(document), do: Address.from_map(document)
end
