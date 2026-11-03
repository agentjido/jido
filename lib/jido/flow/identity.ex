defmodule Jido.Flow.Identity do
  @moduledoc false

  alias Jido.Flow
  alias Jido.Flow.Definition
  alias Jido.Flow.Graph

  @identity_version 1

  @doc false
  @spec semantic_digest(Flow.t()) :: String.t()
  def semantic_digest(%Flow{} = flow) do
    semantic_digest(flow, Graph.canonical_components(flow.components))
  end

  @doc false
  @spec semantic_digest(Flow.t(), [Definition.named_component()]) :: String.t()
  def semantic_digest(%Flow{} = flow, ordered_components) do
    flow
    |> identity_data(ordered_components)
    |> identity_hash()
    |> Base.encode16(case: :lower)
  end

  @doc false
  @spec for_flow(Flow.t()) :: map()
  def for_flow(%Flow{} = flow) do
    flow
    |> identity_data(Graph.canonical_components(flow.components))
    |> identity()
  end

  defp identity_data(flow, ordered_components) do
    %{
      version: @identity_version,
      name: flow.name,
      schema: flow.schema,
      output_schema: flow.output_schema,
      components: Enum.map(ordered_components, &component_identity/1),
      output: flow.output
    }
  end

  # Needs keep their authored order as data, but they form a set of control
  # dependencies, so their order does not change semantic identity.
  defp component_identity(named_component) do
    named_component
    |> Definition.component_to_definition()
    |> Map.delete(:meta)
    |> sort_needs()
  end

  defp sort_needs(%{needs: needs} = definition) when is_list(needs),
    do: %{definition | needs: Enum.sort(needs)}

  defp sort_needs(definition), do: definition

  @doc false
  @spec identity(map()) :: %{
          version: 1,
          algorithm: :sha256,
          digest: String.t(),
          uuid: String.t()
        }
  def identity(canonical_identity_map) when is_map(canonical_identity_map) do
    raw_digest = identity_hash(canonical_identity_map)

    %{
      version: @identity_version,
      algorithm: :sha256,
      digest: Base.encode16(raw_digest, case: :lower),
      uuid: Jido.Id.uuid8(raw_digest)
    }
  end

  defp identity_hash(data), do: hash_term({:jido_flow_identity, @identity_version, data})

  defp hash_term(term) do
    case :erlang.term_to_iovec(term, [:deterministic]) do
      [bytes] ->
        :crypto.hash(:sha256, bytes)

      segments ->
        segments
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()
    end
  end
end
