Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("trim_and_compact.ex", __DIR__)

defmodule Jido.Examples.ContextMemory.TrimAndCompactTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ContextMemory.TrimAndCompact
  alias Jido.Examples.Support.OfflineInferenceClient

  @history [
    %{role: :user, content: "Set up my account."},
    %{role: :assistant, content: "The account is ready."},
    %{role: :user, content: "Explain the bill."},
    %{role: :assistant, content: "The bill has two line items."},
    %{role: :user, content: "What should I do next?"}
  ]

  test "keeps the newest bounded history and compacts only dropped messages" do
    assert {:ok, result} =
             Jido.Exec.run(
               TrimAndCompact,
               %{history: @history, max_messages: 2, max_bytes: 100},
               %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert result.retained == Enum.take(@history, -2)
    assert result.dropped == Enum.take(@history, 3)
    assert result.full_history_count == 5
    assert result.summary == "Earlier discussion covered account setup and billing."
    assert result.compacted_source_messages == 3
    assert result.compaction_model_calls == 1
  end

  test "trimming is deterministic and does not change the full input history" do
    input = %{history: @history, max_messages: 3, max_bytes: 60}
    context = %{jido_ai_inference_client: OfflineInferenceClient}

    assert {:ok, first} = Jido.Exec.run(TrimAndCompact, input, context)
    assert {:ok, second} = Jido.Exec.run(TrimAndCompact, input, context)
    assert first == second
    assert input.history == @history
  end
end
