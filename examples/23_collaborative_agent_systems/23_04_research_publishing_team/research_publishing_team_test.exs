Code.require_file("research_publishing_team.ex", __DIR__)

defmodule Jido.Examples.Collaboration.ResearchTeamTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Collaboration.ResearchTeam

  test "parallel research, one reducer, and one bounded revision produce an approved draft" do
    sources = [
      %{source_id: "source-a", fail: false},
      %{source_id: "source-b", fail: false}
    ]

    assert {:ok, result} = ResearchTeam.run("research-1", "Agent density", sources)

    assert Enum.map(result.evidence, & &1.source_id) == ["source-a", "source-b"]
    assert result.finding.finding == "2 supported findings"
    assert result.publication.draft.revision == 1
    assert result.publication.review.decision == :approve
    assert result.budgets == %{researchers: 2, revisions: 1}
  end

  test "one failed researcher is isolated when enough evidence remains" do
    sources = [
      %{source_id: "source-a", fail: true},
      %{source_id: "source-b", fail: false}
    ]

    assert {:ok, result} = ResearchTeam.run("research-2", "Durable Agents", sources)
    assert Enum.map(result.evidence, & &1.source_id) == ["source-b"]
    assert result.finding.finding == "1 supported findings"
    assert result.publication.review.decision == :approve
  end
end
