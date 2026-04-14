defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.IngestIssueAction do
  @moduledoc false

  use Jido.Action,
    name: "ingest_issue",
    schema: [
      issue_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      title: [type: :string, required: true],
      body: [type: :string, required: true],
      labels: [type: {:list, :string}, default: []],
      event_type: [type: :string, default: "issue_opened"]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts
  alias Examples.PhoenixIssueTriage.IssueTriage.Policy
  alias Jido.Agent.StateOp

  def run(params, %{agent: agent, state: state}) do
    updated_agent = Artifacts.remember_issue(agent, params)
    requires_research = Policy.requires_research?(params.body, params.labels)
    webhook_count = get_in(state, [:ops, :webhook_event_count]) || 0

    {:ok,
     %{
       issue_id: params.issue_id,
       repo: params.repo,
       title: params.title,
       body: params.body,
       labels: params.labels,
       status: :ingested,
       current_stage: :ingested,
       requires_research?: requires_research
     },
     [
       StateOp.set_path([:ops, :webhook_event_count], webhook_count + 1),
       StateOp.set_path([:ops, :last_webhook_event], params.event_type)
       | Artifacts.artifact_ops(updated_agent)
     ]}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.HandleTriageCompletedAction do
  @moduledoc false

  use Jido.Action,
    name: "handle_triage_completed",
    schema: [
      issue_id: [type: :string, required: true],
      summary: [type: :string, required: true],
      classification: [type: :atom, required: true],
      priority: [type: :atom, required: true],
      requires_research: [type: :boolean, default: false]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts

  def run(params, %{agent: agent}) do
    updated_agent =
      Artifacts.remember_triage(agent, %{
        issue_id: params.issue_id,
        classification: params.classification,
        priority: params.priority,
        requires_research?: params.requires_research,
        summary: params.summary
      })

    {:ok,
     %{
       triage_summary: params.summary,
       classification: params.classification,
       priority: params.priority,
       requires_research?: params.requires_research,
       status: :triaged,
       current_stage: :triaged
     }, Artifacts.artifact_ops(updated_agent)}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.HandleResearchCompletedAction do
  @moduledoc false

  use Jido.Action,
    name: "handle_research_completed",
    schema: [
      issue_id: [type: :string, required: true],
      research_summary: [type: :string, required: true],
      confidence: [type: :atom, default: :medium]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts

  def run(params, %{agent: agent}) do
    updated_agent =
      Artifacts.remember_research(agent, %{
        issue_id: params.issue_id,
        research_summary: params.research_summary,
        confidence: params.confidence
      })

    {:ok,
     %{
       research_summary: params.research_summary,
       research_confidence: params.confidence,
       status: :researched,
       current_stage: :researched
     }, Artifacts.artifact_ops(updated_agent)}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.HandleReviewCompletedAction do
  @moduledoc false

  use Jido.Action,
    name: "handle_review_completed",
    schema: [
      issue_id: [type: :string, required: true],
      review_outcome: [type: :atom, required: true],
      review_summary: [type: :string, required: true]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts

  def run(params, %{agent: agent}) do
    updated_agent =
      Artifacts.remember_review(agent, %{
        issue_id: params.issue_id,
        review_outcome: params.review_outcome,
        review_summary: params.review_summary
      })

    {:ok,
     %{
       review_outcome: params.review_outcome,
       review_summary: params.review_summary,
       status: params.review_outcome,
       current_stage: :reviewed
     }, Artifacts.artifact_ops(updated_agent)}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.HandlePublishCompletedAction do
  @moduledoc false

  use Jido.Action,
    name: "handle_publish_completed",
    schema: [
      issue_id: [type: :string, required: true],
      artifact_ref: [type: :string, required: true]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts

  def run(params, %{agent: agent}) do
    updated_agent =
      Artifacts.remember_publish(agent, %{
        issue_id: params.issue_id,
        artifact_ref: params.artifact_ref
      })

    {:ok,
     %{
       published_artifact: params.artifact_ref,
       status: :published,
       current_stage: :published
     }, Artifacts.artifact_ops(updated_agent)}
  end
end
