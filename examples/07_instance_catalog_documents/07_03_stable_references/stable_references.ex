defmodule Jido.Examples.StableReferences do
  @moduledoc "Builds and serializes public stable Agent addresses."

  alias Jido.Agent.Ref

  def build(instance, id, partition), do: Jido.agent_ref(instance, id, partition: partition)
  def encode(%Ref{} = ref), do: Ref.to_map(ref)
  def decode(document), do: Ref.from_map(document)
end
