defmodule Jido.AgentServer.DurableTurn.JoinCompletedRef do
  @moduledoc false

  alias Runic.Workflow.Events.JoinCompleted

  @enforce_keys [
    :join_hash,
    :result_fact_hash,
    :result_ancestry,
    :contribution_fact_hashes,
    :weight
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          join_hash: term(),
          result_fact_hash: term(),
          result_ancestry: {term(), term()} | nil,
          contribution_fact_hashes: [term()] | nil,
          weight: non_neg_integer()
        }

  @spec from_event(JoinCompleted.t()) :: t()
  def from_event(%JoinCompleted{} = event) do
    struct!(__MODULE__, Map.from_struct(event) |> Map.delete(:result_value))
  end
end

defimpl Runic.Workflow.EventApplicator,
  for: Jido.AgentServer.DurableTurn.JoinCompletedRef do
  alias Runic.Workflow
  alias Runic.Workflow.FactRef
  alias Runic.Identity

  def apply(event, workflow) do
    join = Map.get(workflow.graph.vertices, event.join_hash)

    ref = %FactRef{
      id: fact_id(event.result_fact_hash),
      hash: event.result_fact_hash,
      ancestry: event.result_ancestry
    }

    if join do
      workflow
      |> Workflow.log_fact(ref)
      |> Workflow.draw_connection(join, ref, :produced,
        weight: event.weight || 0,
        properties: %{join_contribution_fact_hashes: event.contribution_fact_hashes}
      )
    else
      workflow
    end
  end

  defp fact_id(
         %Identity{
           scheme: :sha256,
           version: 1,
           domain: :fact_occurrence,
           digest: digest
         } = id
       )
       when is_binary(digest) and byte_size(digest) == 32,
       do: id

  defp fact_id(%Identity{} = id) do
    raise ArgumentError, "expected a valid Fact occurrence identity, got: #{inspect(id)}"
  end

  defp fact_id(_legacy_hash), do: nil
end
