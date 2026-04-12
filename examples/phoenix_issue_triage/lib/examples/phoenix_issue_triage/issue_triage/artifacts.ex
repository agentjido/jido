defmodule Examples.PhoenixIssueTriage.IssueTriage.Artifacts do
  @moduledoc """
  Persists workflow artifacts into agent memory and thread state.

  This module exists because action return values can update root state directly,
  but memory/thread live under default plugin keys and need explicit `StateOp`
  updates after helper calls mutate the in-memory agent struct.
  """

  alias Jido.Agent
  alias Jido.Agent.StateOp
  alias Jido.Memory.Agent, as: MemoryAgent
  alias Jido.Thread.Agent, as: ThreadAgent

  @spec artifact_ops(Agent.t()) :: [struct()]
  def artifact_ops(%Agent{} = agent) do
    []
    |> maybe_put_memory(agent)
    |> maybe_put_thread(agent)
    |> Enum.reverse()
  end

  @spec remember_issue(Agent.t(), map()) :: Agent.t()
  def remember_issue(%Agent{} = agent, attrs) do
    labels = normalize_labels(Map.get(attrs, :labels, []))

    issue = %{
      issue_id: Map.get(attrs, :issue_id, ""),
      repo: Map.get(attrs, :repo, ""),
      title: Map.get(attrs, :title, ""),
      body: Map.get(attrs, :body, ""),
      labels: labels,
      event_type: Map.get(attrs, :event_type, "issue_opened")
    }

    agent
    |> ensure_workflow_spaces()
    |> MemoryAgent.put_in_space(:world, :current_issue, issue)
    |> MemoryAgent.append_to_space(:tasks, %{
      id: "triage:#{issue.issue_id}",
      type: :triage,
      status: :pending
    })
    |> MemoryAgent.append_to_space(:events, %{kind: :issue_ingested, issue_id: issue.issue_id})
    |> ThreadAgent.append(%{kind: :issue_ingested, payload: issue})
  end

  @spec remember_triage(Agent.t(), map()) :: Agent.t()
  def remember_triage(%Agent{} = agent, attrs) do
    summary = %{
      issue_id: Map.get(attrs, :issue_id, ""),
      classification: Map.get(attrs, :classification),
      priority: Map.get(attrs, :priority),
      requires_research?: Map.get(attrs, :requires_research?, false),
      summary: Map.get(attrs, :summary, "")
    }

    agent
    |> ensure_workflow_spaces()
    |> MemoryAgent.put_in_space(:world, :triage, summary)
    |> MemoryAgent.append_to_space(:events, %{kind: :triage_completed, issue_id: summary.issue_id})
    |> ThreadAgent.append(%{kind: :triage_completed, payload: summary})
  end

  @spec remember_research(Agent.t(), map()) :: Agent.t()
  def remember_research(%Agent{} = agent, attrs) do
    summary = %{
      issue_id: Map.get(attrs, :issue_id, ""),
      research_summary: Map.get(attrs, :research_summary, ""),
      confidence: Map.get(attrs, :confidence, :medium)
    }

    agent
    |> ensure_workflow_spaces()
    |> MemoryAgent.put_in_space(:world, :research, summary)
    |> MemoryAgent.append_to_space(:events, %{
      kind: :research_completed,
      issue_id: summary.issue_id
    })
    |> ThreadAgent.append(%{kind: :research_completed, payload: summary})
  end

  @spec remember_review(Agent.t(), map()) :: Agent.t()
  def remember_review(%Agent{} = agent, attrs) do
    summary = %{
      issue_id: Map.get(attrs, :issue_id, ""),
      review_outcome: Map.get(attrs, :review_outcome, :changes_requested),
      review_summary: Map.get(attrs, :review_summary, "")
    }

    agent
    |> ensure_workflow_spaces()
    |> MemoryAgent.put_in_space(:world, :review, summary)
    |> MemoryAgent.append_to_space(:events, %{kind: :review_completed, issue_id: summary.issue_id})
    |> ThreadAgent.append(%{kind: :review_completed, payload: summary})
  end

  @spec remember_publish(Agent.t(), map()) :: Agent.t()
  def remember_publish(%Agent{} = agent, attrs) do
    summary = %{
      issue_id: Map.get(attrs, :issue_id, ""),
      artifact_ref: Map.get(attrs, :artifact_ref, "")
    }

    agent
    |> ensure_workflow_spaces()
    |> MemoryAgent.put_in_space(:world, :publish, summary)
    |> MemoryAgent.append_to_space(:events, %{
      kind: :publish_completed,
      issue_id: summary.issue_id
    })
    |> ThreadAgent.append(%{kind: :publish_completed, payload: summary})
  end

  defp ensure_workflow_spaces(agent) do
    agent
    |> MemoryAgent.ensure()
    |> MemoryAgent.ensure_space(:events, [])
  end

  defp normalize_labels(labels) when is_list(labels) do
    Enum.map(labels, &to_string/1)
  end

  defp normalize_labels(_other), do: []

  defp maybe_put_memory(ops, agent) do
    case MemoryAgent.get(agent) do
      nil -> ops
      memory -> [StateOp.set_path([MemoryAgent.key()], memory) | ops]
    end
  end

  defp maybe_put_thread(ops, agent) do
    case ThreadAgent.get(agent) do
      nil -> ops
      thread -> [StateOp.set_path([ThreadAgent.key()], thread) | ops]
    end
  end
end
