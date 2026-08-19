defmodule Examples.PhoenixIssueTriage.IssueTriage.Agents.ResearcherAgent do
  @moduledoc """
  Example agent for deeper repository research.
  """

  use Jido.Agent,
    name: "examples_phoenix_issue_triage_researcher",
    schema: [
      role: [type: :string, default: "researcher"],
      last_issue_id: [type: :string, default: ""],
      research_summary: [type: :string, default: ""],
      status: [type: :atom, default: :idle]
    ],
    signal_routes: [
      {"issue.research.requested",
       Examples.PhoenixIssueTriage.IssueTriage.Actions.ProcessResearchRequestAction}
    ]
end
