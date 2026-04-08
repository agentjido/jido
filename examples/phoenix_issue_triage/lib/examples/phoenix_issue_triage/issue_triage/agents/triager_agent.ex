defmodule Examples.PhoenixIssueTriage.IssueTriage.Agents.TriagerAgent do
  @moduledoc """
  Example agent for issue classification.
  """

  use Jido.Agent,
    name: "examples_phoenix_issue_triage_triager",
    schema: [
      role: [type: :string, default: "triager"],
      last_issue_id: [type: :string, default: ""],
      classification: [type: :atom, default: :unknown],
      priority: [type: :atom, default: :normal],
      last_summary: [type: :string, default: ""],
      status: [type: :atom, default: :idle]
    ],
    signal_routes: [
      {"issue.triage.requested",
       Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessTriageRequestAction}
    ]
end
