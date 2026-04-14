defmodule Examples.PhoenixIssueTriage.IssueTriage.Agents.ReviewerAgent do
  @moduledoc """
  Example agent for human or automated review.
  """

  use Jido.Agent,
    name: "examples_phoenix_issue_triage_reviewer",
    schema: [
      role: [type: :string, default: "reviewer"],
      last_issue_id: [type: :string, default: ""],
      review_outcome: [type: :atom, default: :pending],
      review_summary: [type: :string, default: ""],
      status: [type: :atom, default: :idle]
    ],
    signal_routes: [
      {"issue.review.requested",
       Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessReviewRequestAction}
    ]
end
