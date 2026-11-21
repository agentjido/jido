defmodule Jido.Examples.Operations.DistributedIdentityAgent do
  @moduledoc "A logical Agent used to separate identity from local process location."

  use Jido.Agent, name: "operations_distributed_identity_agent"
end

defmodule Jido.Examples.Operations.DistributionBoundary do
  @moduledoc "Encodes and decodes stable logical Agent identity."

  @doc "Returns the versioned public map for one Address."
  def encode_address(address), do: Jido.Agent.Address.to_map(address)

  @doc "Validates one versioned public Address map."
  def decode_address(map), do: Jido.Agent.Address.from_map(map)
end
