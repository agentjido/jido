Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("persistence_and_restoration.ex", __DIR__)

defmodule Jido.Examples.Conversation.RestorationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.Conversation.{RestorableAgent, Restoration}
  alias Jido.Examples.Support.OfflineInferenceClient

  test "a restored Agent retains the complete committed conversation" do
    source =
      RestorableAgent.instantiate!(id: "restorable-#{System.unique_integer([:positive])}")

    request =
      RestorableAgent.request_signal!(%{
        input: "Remember this exchange.",
        options: %{offline_response: "Exchange recorded."}
      })

    assert {:ok, candidate, [_reply]} =
             RestorableAgent.cmd(source, request, context: %{jido_ai_inference_client: OfflineInferenceClient})

    assert {:ok, snapshot} = Restoration.snapshot(candidate)
    assert {:ok, restored} = Restoration.restore(snapshot)
    assert restored == candidate

    assert {:ok, messages} = Jido.AI.Thread.Projection.messages(restored.state.session)
    assert Enum.map(messages, & &1.content) == ["Remember this exchange.", "Exchange recorded."]
  end
end
