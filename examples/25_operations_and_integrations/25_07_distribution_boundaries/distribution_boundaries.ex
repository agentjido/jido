defmodule Jido.Examples.Operations.DistributedIdentityAgent do
  @moduledoc "A logical Agent used to separate identity from local process location."

  use Jido.Agent, name: "operations_distributed_identity_agent"
end

defmodule Jido.Examples.Operations.DistributionBoundary do
  @moduledoc "Encodes and decodes stable logical Agent identity."

  @doc "Returns the versioned public map for one Ref."
  def encode_ref(ref), do: Jido.Agent.Ref.to_map(ref)

  @doc "Validates one versioned public Ref map."
  def decode_ref(map), do: Jido.Agent.Ref.from_map(map)
end
