Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("conversation_history.ex", __DIR__)

defmodule Jido.Examples.AI.ConversationHistoryTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.ConversationHistory
  alias Jido.Examples.Support.OfflineInferenceClient

  test "a later request keeps committed history and exposes a safe UI projection" do
    first = ConversationHistory.new(id: "history-#{System.unique_integer([:positive])}")

    assert {:ok, first, [_reply]} =
             ConversationHistory.Agent.cmd(
               first,
               request("First question", "First answer."),
               context: %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert {:ok, second, [_reply]} =
             ConversationHistory.Agent.cmd(
               first,
               request("Second question", "Second answer."),
               context: %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert {:ok, public} = ConversationHistory.public_messages(second.state.session)

    assert public == [
             %{role: "user", text: "First question"},
             %{role: "assistant", text: "First answer."},
             %{role: "user", text: "Second question"},
             %{role: "assistant", text: "Second answer."}
           ]

    refute Map.has_key?(hd(public), :metadata)
    refute Map.has_key?(hd(public), :refs)
    assert second.state.session.thread.rev > first.state.session.thread.rev
  end

  defp request(input, output) do
    ConversationHistory.Agent.request_signal!(%{
      input: input,
      options: %{offline_response: output}
    })
  end
end
