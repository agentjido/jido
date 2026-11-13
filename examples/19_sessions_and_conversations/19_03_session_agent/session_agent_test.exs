Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("session_agent.ex", __DIR__)

defmodule Jido.Examples.AI.SessionAgentTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.SessionAgent
  alias Jido.Examples.Support.OfflineInferenceClient

  test "the first successful request creates and projects Agent-owned Session state" do
    agent = SessionAgent.new(id: "session-agent-#{System.unique_integer([:positive])}")
    assert agent.state == %{session: nil}

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             SessionAgent.Agent.cmd(
               agent,
               SessionAgent.Agent.request_signal!(%{
                 input: "What does a Session own?",
                 options: %{offline_response: "A Session owns one Thread."}
               }),
               context: %{jido_ai_inference_client: OfflineInferenceClient}
             )

    assert reply.data.output == "A Session owns one Thread."
    assert %Jido.Session{status: :open, thread: %Jido.Thread{}} = next.state.session

    assert {:ok, messages} = Jido.AI.Thread.Projection.messages(next.state.session)

    assert Enum.map(messages, &{&1.role, &1.content}) == [
             {:user, "What does a Session own?"},
             {:assistant, "A Session owns one Thread."}
           ]
  end
end
