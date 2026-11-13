Code.require_file("specialist_pipeline.ex", __DIR__)

defmodule Jido.Examples.Collaboration.SpecialistPipelineTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Collaboration.SpecialistPipeline

  test "three pure Agents hand off one correlated mission" do
    assert {:ok, result} =
             SpecialistPipeline.run("mission-7", "Database requests are slow")

    assert result.artifacts.classification.category == "database"
    assert result.artifacts.diagnosis.cause == "connection pool saturation"
    assert result.artifacts.response.action == "increase pool capacity"

    assert Enum.all?(Map.values(result.artifacts), &(&1.mission_id == "mission-7"))
    assert result.agents.classifier.state.handled == 1
  end

  test "a specialist failure stops before the next handoff" do
    assert {:error, %Jido.Error.ExecutionError{message: "injected diagnostician failure"}} =
             SpecialistPipeline.run("mission-8", "Database requests are slow", fail_diagnosis: true)
  end
end
