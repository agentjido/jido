Code.require_file("agent.ex", __DIR__)

defmodule Jido.Examples.AI.StreamingTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :integration

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.Streaming.Agent
  alias Jido.Test.Examples.AIModel

  test "streaming emits ordered Signals and commits one answer" do
    AIModel.expect_stream("Streamed answer")
    agent = Agent.instantiate!(id: unique_id("streaming-ai"))
    request = Agent.request_signal!(%{input: "Stream this", stream: true})

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(agent, request, context: %{jido_ai_dispatch: {:pid, target: self()}})

    signals = AIModel.receive_stream()
    assert List.first(signals).type == "jido.ai.model.stream.started"
    assert List.last(signals).type == "jido.ai.model.stream.completed"
    assert Enum.any?(signals, &(&1.type == "jido.ai.model.stream.chunk"))
    assert Enum.map(signals, & &1.data.sequence) == Enum.to_list(0..(length(signals) - 1))
    assert reply.data.output == "Streamed answer"
    assert next.state.session.thread.rev > 0
  end
end
