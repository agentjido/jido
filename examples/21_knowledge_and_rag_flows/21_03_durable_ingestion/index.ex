defmodule Jido.Examples.RAG.DurableIngestion.Index do
  @moduledoc "An offline index adapter that loses the first acknowledgement."

  use Agent

  def start_link(options), do: Agent.start_link(fn -> %{} end, options)

  def apply_plan(index, plan) do
    Agent.get_and_update(index, fn revisions ->
      case Map.fetch(revisions, plan.idempotency_key) do
        :error ->
          acknowledgement = %{document_id: plan.document_id, revision: plan.revision, index_revision: 41}
          {{:error, :acknowledgement_lost}, Map.put(revisions, plan.idempotency_key, {plan, acknowledgement})}

        {:ok, {^plan, acknowledgement}} ->
          {{:ok, acknowledgement}, revisions}

        {:ok, _} ->
          {{:error, :revision_conflict}, revisions}
      end
    end)
  end

  def revisions(index), do: Agent.get(index, & &1)
end
