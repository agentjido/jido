defmodule Jido.Examples.Topology.PlacementPolicy.Move do
  @moduledoc "Requests exact placement for one topology Agent or group member."
  use Jido.Agent.Directive

  @enforce_keys [:topology_id, :target, :node]
  defstruct [:topology_id, :target, :member, :node]

  @impl Jido.Agent.Directive
  def validate(%__MODULE__{topology_id: id, target: target, node: target_node} = directive)
      when is_binary(id) and byte_size(id) > 0 and not is_nil(target) and
             is_atom(target_node) and target_node not in [nil, true, false] do
    {:ok, directive}
  end

  def validate(_directive), do: {:error, :invalid_topology_placement}
end
