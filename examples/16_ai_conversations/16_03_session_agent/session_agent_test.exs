Code.require_file("session_agent.ex", __DIR__)

defmodule Jido.Examples.AI.SessionAgentTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :integration

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.SessionAgent
  alias Jido.Test.Examples.AIModel

  test "the first successful request creates and commits Agent-owned Session state" do
    AIModel.expect_text("A Session owns one Thread.")
    agent = SessionAgent.new(id: unique_id("session-agent"))
    assert agent.state == %{session: nil}

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             SessionAgent.Agent.cmd(
               agent,
               SessionAgent.Agent.request_signal!(%{input: "What does a Session own?"})
             )

    assert reply.data.output == "A Session owns one Thread."
    assert %Jido.Session{status: :open, thread: %Jido.Thread{}} = next.state.session
    assert {:ok, snapshot} = Jido.Persistence.snapshot(next)
    assert {:ok, restored} = Jido.Persistence.restore(snapshot)
    assert restored == next
  end
end
