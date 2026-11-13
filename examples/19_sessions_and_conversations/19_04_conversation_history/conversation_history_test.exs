Code.require_file("conversation_history.ex", __DIR__)

defmodule Jido.Examples.AI.ConversationHistoryTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :integration

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.ConversationHistory
  alias Jido.Test.Examples.AIModel

  test "the second request includes the first committed exchange" do
    owner = self()
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    expect(ReqLLM, :generate_text, 2, fn model, context, _options ->
      call = Agent.get_and_update(calls, fn count -> {count + 1, count + 1} end)
      messages = ReqLLM.Context.to_list(context)
      send(owner, {:model_context, call, Enum.map(messages, &{&1.role, message_text(&1)})})
      text = if call == 1, do: "First answer.", else: "Second answer."
      {:ok, AIModel.text_response(model, context, text, "history-#{call}")}
    end)

    first = ConversationHistory.new(id: unique_id("history"))

    assert {:ok, first, [_reply]} =
             ConversationHistory.Agent.cmd(
               first,
               ConversationHistory.Agent.request_signal!(%{input: "First question"})
             )

    assert {:ok, second, [_reply]} =
             ConversationHistory.Agent.cmd(
               first,
               ConversationHistory.Agent.request_signal!(%{input: "Second question"})
             )

    assert_receive {:model_context, 1, [{:system, _}, {:user, "First question"}]}

    assert_receive {:model_context, 2,
                    [
                      {:system, _},
                      {:user, "First question"},
                      {:assistant, "First answer."},
                      {:user, "Second question"}
                    ]}

    assert second.state.session.thread.rev > first.state.session.thread.rev
  end

  defp message_text(message), do: Enum.map_join(message.content, &(&1.text || ""))
end
