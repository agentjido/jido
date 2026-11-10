Code.require_file("../../support/loader.exs", __DIR__)
unless Code.ensure_loaded?(Jido.Test.Examples.AIModel), do: Code.require_file("../../support/ai_model.exs", __DIR__)

Jido.Test.Examples.Loader.require_source!("16_ai_conversations/16_01_thread_agent/thread_agent.ex")

defmodule Jido.Examples.AI.ThreadAgentTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("16_ai_conversations/16_01_thread_agent/thread_agent.ex")
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.AI.Thread.Projection
  alias Jido.Examples.AI.ThreadAgent.Agent
  alias Jido.Test.Examples.AIModel

  test "one completed request commits a portable conversation Thread" do
    AIModel.expect_text("OTP uses supervised processes.")
    agent = Agent.instantiate!(id: unique_id("thread-agent"))

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(agent, Agent.request_signal!(%{input: "What is OTP?"}))

    assert reply.data.output == "OTP uses supervised processes."
    session = next.state.session
    assert %Jido.Session{status: :open} = session
    assert {:ok, messages} = Projection.messages(session)
    assert Enum.map(messages, & &1.role) == [:user, :assistant]

    assert Enum.map(messages, & &1.content) == [
             "What is OTP?",
             "OTP uses supervised processes."
           ]
  end

  test "a provider failure records an outcome without a completed exchange" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options -> {:error, :offline_failure} end)
    agent = Agent.instantiate!(id: unique_id("thread-failure"))

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(agent, Agent.request_signal!(%{input: "Fail this request"}))

    assert reply.data.status == :failed
    assert {:ok, []} = Projection.messages(next.state.session)
    assert Enum.any?(next.state.session.thread.entries, &(&1.kind == :ai_request_outcome))
  end
end
