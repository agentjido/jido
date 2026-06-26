defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessTriageRequestAction do
  @moduledoc false

  use Jido.Action,
    name: "process_triage_request",
    schema: [
      issue_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      title: [type: :string, required: true],
      body: [type: :string, required: true],
      labels: [type: {:list, :string}, default: []],
      requires_research: [type: :boolean, default: false]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts
  alias Examples.PhoenixIssueTriage.IssueTriage.Policy
  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(params, %{agent: agent}) do
    classification = Policy.classify(params.title, params.body, params.labels)
    priority = Policy.priority(params.body, params.labels)

    summary =
      "Triaged #{params.issue_id} as #{classification} with #{priority} priority."

    updated_agent =
      agent
      |> Artifacts.remember_issue(params)
      |> Artifacts.remember_triage(%{
        issue_id: params.issue_id,
        classification: classification,
        priority: priority,
        requires_research?: params.requires_research,
        summary: summary
      })

    signal =
      Signal.new!(
        "issue.triage.completed",
        %{
          issue_id: params.issue_id,
          summary: summary,
          classification: classification,
          priority: priority,
          requires_research: params.requires_research
        },
        source: "/examples/phoenix_issue_triage/issue_triage/triager"
      )

    {:ok,
     %{
       last_issue_id: params.issue_id,
       classification: classification,
       priority: priority,
       last_summary: summary,
       status: :triaged
     },
     Artifacts.artifact_ops(updated_agent) ++
       [Directive.emit_to_parent(updated_agent, signal)]}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessResearchRequestAction do
  @moduledoc false

  use Jido.Action,
    name: "process_research_request",
    schema: [
      issue_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      title: [type: :string, required: true],
      body: [type: :string, required: true],
      triage_summary: [type: :string, required: true],
      classification: [type: :atom, required: true],
      priority: [type: :atom, required: true]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts
  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(params, %{agent: agent}) do
    research_summary =
      "Reviewed repository context for #{params.issue_id} and confirmed #{params.classification} handling path."

    updated_agent =
      agent
      |> Artifacts.remember_research(%{
        issue_id: params.issue_id,
        research_summary: research_summary,
        confidence: :high
      })

    signal =
      Signal.new!(
        "issue.research.completed",
        %{
          issue_id: params.issue_id,
          research_summary: research_summary,
          confidence: :high
        },
        source: "/examples/phoenix_issue_triage/issue_triage/researcher"
      )

    {:ok,
     %{
       last_issue_id: params.issue_id,
       research_summary: research_summary,
       status: :researched
     },
     Artifacts.artifact_ops(updated_agent) ++
       [Directive.emit_to_parent(updated_agent, signal)]}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessReviewRequestAction do
  @moduledoc false

  use Jido.Action,
    name: "process_review_request",
    schema: [
      issue_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      triage_summary: [type: :string, required: true],
      classification: [type: :atom, required: true],
      priority: [type: :atom, required: true],
      research_summary: [type: :string, default: ""]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts
  alias Examples.PhoenixIssueTriage.IssueTriage.Policy
  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(params, %{agent: agent}) do
    review_outcome = Policy.review_outcome(params.priority, params.research_summary)

    review_summary =
      case review_outcome do
        :approved -> "Approved #{params.issue_id} for next-step handling."
        :changes_requested -> "Requested more context before approving #{params.issue_id}."
      end

    updated_agent =
      agent
      |> Artifacts.remember_review(%{
        issue_id: params.issue_id,
        review_outcome: review_outcome,
        review_summary: review_summary
      })

    signal =
      Signal.new!(
        "issue.review.completed",
        %{
          issue_id: params.issue_id,
          review_outcome: review_outcome,
          review_summary: review_summary
        },
        source: "/examples/phoenix_issue_triage/issue_triage/reviewer"
      )

    {:ok,
     %{
       last_issue_id: params.issue_id,
       review_outcome: review_outcome,
       review_summary: review_summary,
       status: :reviewed
     },
     Artifacts.artifact_ops(updated_agent) ++
       [Directive.emit_to_parent(updated_agent, signal)]}
  end
end

defmodule Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessPublishRequestAction do
  @moduledoc false

  use Jido.Action,
    name: "process_publish_request",
    schema: [
      issue_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      triage_summary: [type: :string, required: true],
      review_summary: [type: :string, required: true]
    ]

  alias Examples.PhoenixIssueTriage.IssueTriage.Artifacts
  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(params, %{agent: agent}) do
    artifact_ref = "triage-note://#{params.repo}/#{params.issue_id}"

    updated_agent =
      agent
      |> Artifacts.remember_publish(%{
        issue_id: params.issue_id,
        artifact_ref: artifact_ref
      })

    signal =
      Signal.new!(
        "issue.publish.completed",
        %{
          issue_id: params.issue_id,
          artifact_ref: artifact_ref
        },
        source: "/examples/phoenix_issue_triage/issue_triage/publisher"
      )

    {:ok,
     %{
       last_issue_id: params.issue_id,
       artifact_ref: artifact_ref,
       status: :published
     },
     Artifacts.artifact_ops(updated_agent) ++
       [Directive.emit_to_parent(updated_agent, signal)]}
  end
end
