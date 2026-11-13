Code.require_file("failed_and_incomplete.ex", __DIR__)

defmodule Jido.Examples.Conversation.FailedAndIncompleteTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AI.Thread.Projection
  alias Jido.Examples.Conversation.FailedAndIncomplete

  test "messages from a failed request remain evidence but leave later model context" do
    assert {:ok, session} = FailedAndIncomplete.failed_request()
    assert {:ok, []} = Projection.messages(session)
    assert length(session.thread.entries) == 2

    assert {:ok, explanation} = Projection.explain(session, %{})
    assert [%{state: :excluded, reason: :request_not_completed}] = explanation.decisions
  end

  test "an unmatched tool request is excluded as an incomplete exchange" do
    assert {:ok, session} = FailedAndIncomplete.incomplete_tool_exchange()
    assert {:ok, explanation} = Projection.explain(session, %{})

    assert Enum.any?(explanation.decisions, fn decision ->
             decision.state == :excluded and decision.reason == :incomplete_tool_exchange
           end)

    assert Enum.all?(explanation.messages, &(&1.role != :assistant))
  end
end
