Code.require_file("../../support/loader.exs", __DIR__)
unless Code.ensure_loaded?(JidoTest.Examples.AIModel), do: Code.require_file("../../support/ai_model.exs", __DIR__)

JidoTest.Examples.Loader.require_source!("15_ai_basics/15_01_basic_agent/agent.ex")

defmodule JidoTest.Examples.AI.BasicAgentTest do
  use JidoTest.Case, async: false
  import Mimic

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("15_ai_basics/15_01_basic_agent/agent.ex")
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.BasicAgent.Agent, as: Example
  alias JidoTest.Examples.AIModel

  test "the Agent stores current reasoning defaults" do
    assert %{defaults: defaults, tools: []} = Example.explain()
    assert defaults.model == "openai:gpt-4o-mini"
    assert defaults.instructions == "Reply in one short sentence."
  end

  test "one offline model result returns a correlated reply" do
    AIModel.expect_text("OTP is a runtime for reliable systems.")
    agent = Example.instantiate!(id: unique_id("basic-ai"))
    request = Example.request_signal!(%{input: "What is OTP?"})

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Example.cmd(agent, request)

    assert reply.data.status == :completed
    assert reply.data.output == "OTP is a runtime for reliable systems."
    assert next.state.session.thread.rev > 0
    assert reply.source == Example.definition().signal_source
  end
end
