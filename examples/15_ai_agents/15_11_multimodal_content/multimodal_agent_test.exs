Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("multimodal_agent.ex", __DIR__)

defmodule Jido.Examples.AI.MultimodalContentTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.MultimodalContent.Agent
  alias Jido.Examples.Support.OfflineInferenceClient

  test "text and image parts reach the normal AI Turn and committed Session" do
    source = Agent.instantiate!(id: "multimodal-#{System.unique_integer([:positive])}")
    image_url = "data:image/png;base64,iVBORw0KGgo="
    assert {:ok, request} = Agent.request("Describe this image", image_url, "image/png")

    assert {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(source, request, context: %{jido_ai_inference_client: OfflineInferenceClient})

    assert reply.data.status == :completed
    assert reply.data.output == "The offline image contains a blue square."

    assert {:ok, [user, assistant]} =
             Jido.AI.Thread.Projection.messages(candidate.state.session)

    assert user.role == :user
    assert Enum.map(user.content, & &1["type"]) == ["text", "image_url"]
    assert Enum.at(user.content, 0)["text"] == "Describe this image"
    assert Enum.at(user.content, 1)["url"] == image_url
    assert Enum.at(user.content, 1)["media_type"] == "image/png"
    assert assistant.role == :assistant
  end
end
