defmodule Examples.PhoenixIssueTriage.IssueTriage.Pod do
  @moduledoc """
  Durable multi-agent runtime definition for issue triage runs.

  In a Phoenix app this is not the module controllers or LiveViews should call
  directly. It defines the runtime shape. The application-facing boundary lives
  in `Examples.PhoenixIssueTriage.IssueTriage`.
  """

  alias Examples.PhoenixIssueTriage.IssueTriage.{Actions, Agents, Plugins}

  use Jido.Pod,
    name: "issue_triage_pod",
    plugins: [Plugins.IssueRunOpsPlugin],
    schema: [
      repo: [type: :string, default: ""],
      issue_id: [type: :string, default: ""],
      title: [type: :string, default: ""],
      body: [type: :string, default: ""],
      labels: [type: {:list, :string}, default: []],
      status: [type: :atom, default: :new],
      current_stage: [type: :atom, default: :new],
      requires_research?: [type: :boolean, default: false],
      triage_summary: [type: :string, default: ""],
      classification: [type: :atom, default: :unknown],
      priority: [type: :atom, default: :normal],
      research_summary: [type: :string, default: ""],
      research_confidence: [type: :atom, default: :medium],
      review_outcome: [type: :atom, default: :pending],
      review_summary: [type: :string, default: ""],
      published_artifact: [type: :string, default: ""]
    ],
    signal_routes: [
      {"jido.sensor.heartbeat", Actions.TrackHeartbeatAction},
      {"issue.webhook.received", Actions.IngestIssueAction},
      {"issue.triage.completed", Actions.HandleTriageCompletedAction},
      {"issue.research.completed", Actions.HandleResearchCompletedAction},
      {"issue.review.completed", Actions.HandleReviewCompletedAction},
      {"issue.publish.completed", Actions.HandlePublishCompletedAction}
    ],
    topology:
      Jido.Pod.Topology.new!(
        name: "issue_triage_pod",
        nodes: %{
          triager: %{
            agent: Agents.TriagerAgent,
            manager: :example_issue_triage_triagers,
            activation: :eager,
            initial_state: %{role: "triager"}
          },
          researcher: %{
            agent: Agents.ResearcherAgent,
            manager: :example_issue_triage_researchers,
            activation: :lazy,
            initial_state: %{role: "researcher"}
          },
          reviewer: %{
            agent: Agents.ReviewerAgent,
            manager: :example_issue_triage_reviewers,
            activation: :lazy,
            initial_state: %{role: "reviewer"}
          }
        },
        links: [
          {:depends_on, :researcher, :triager},
          {:depends_on, :reviewer, :triager},
          {:depends_on, :reviewer, :researcher}
        ]
      )
end
