Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("working_memory_and_recall.ex", __DIR__)

defmodule Jido.Examples.ContextMemory.WorkingMemoryRecallTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ContextMemory.WorkingMemoryRecall
  alias Jido.Examples.Support.OfflineInferenceClient

  @scope %{agent_id: "agent-1", session_id: "session-1", resource_id: "account-7", tenant_id: "tenant-a"}
  @memories [
    %{
      id: "memory-1",
      text: "reports are retained for 30 days",
      scopes: @scope,
      provenance: %{source: "policy-4", revision: 2}
    },
    %{
      id: "memory-2",
      text: "reports are retained for 90 days",
      scopes: Map.put(@scope, :tenant_id, "tenant-b"),
      provenance: %{source: "policy-9", revision: 1}
    }
  ]

  test "recalls only memory from the complete requested scope" do
    assert {:ok, result} =
             Jido.Exec.run(
               WorkingMemoryRecall,
               %{
                 plan: "Answer the retention question.",
                 facts: ["account is active", "account is active"],
                 preferences: %{format: "short"},
                 query: "reports are retained for 30 days",
                 scope: @scope,
                 memories: @memories,
                 limit: 3
               },
               %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert result.working_memory.facts == ["account is active"]
    assert result.working_memory.owner == :application
    assert result.recall.considered == 1

    assert [%{id: "memory-1", score: 1.0, provenance: %{source: "policy-4"}}] =
             result.recall.recalled
  end

  test "a different tenant cannot recall the first tenant memory" do
    scope = Map.put(@scope, :tenant_id, "tenant-b")

    assert {:ok, result} =
             Jido.Exec.run(
               WorkingMemoryRecall,
               %{
                 plan: "Answer.",
                 facts: [],
                 preferences: %{},
                 query: "reports are retained for 90 days",
                 scope: scope,
                 memories: @memories,
                 limit: 1
               },
               %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert [%{id: "memory-2"}] = result.recall.recalled
  end
end
