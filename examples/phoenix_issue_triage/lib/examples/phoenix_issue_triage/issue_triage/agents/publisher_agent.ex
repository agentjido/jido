defmodule Examples.PhoenixIssueTriage.IssueTriage.Agents.PublisherAgent do
  @moduledoc """
  Example agent for publishing the final triage artifact after review approval.
  """

  use Jido.Agent,
    name: "examples_phoenix_issue_triage_publisher",
    schema: [
      role: [type: :string, default: "publisher"],
      last_issue_id: [type: :string, default: ""],
      artifact_ref: [type: :string, default: ""],
      status: [type: :atom, default: :idle]
    ],
    signal_routes: [
      {"issue.publish.requested",
       Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessPublishRequestAction}
    ]
end
