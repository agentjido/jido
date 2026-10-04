defmodule Jido.Examples.Research.DataDefinedTopology.Transport do
  @moduledoc "Moves the selected Topology definition through its public JSON Codec."

  alias Jido.Topology.Codec

  def round_trip(definition) do
    with {:ok, document, registry} <- Codec.encode(definition),
         {:ok, decoded} <- Codec.decode(JSON.decode!(JSON.encode!(document)), registry),
         do: {:ok, decoded, document, registry}
  end
end
