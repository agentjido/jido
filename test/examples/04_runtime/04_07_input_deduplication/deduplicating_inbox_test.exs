defmodule JidoTest.Examples.Runtime.DeduplicatingInboxTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.Examples.DeduplicatingInbox

  test "a duplicate stable event ID does not commit twice", %{jido: jido} do
    quiet_error_policy = fn _reason, _outcome -> :continue end
    agent = start_agent!(jido, DeduplicatingInbox, error_policy: quiet_error_policy)

    assert {:ok, first} =
             DeduplicatingInbox.receive_event(agent,
               input: %{event_id: "event-1", item: %{value: 7}}
             )

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             DeduplicatingInbox.receive_event(agent,
               input: %{event_id: "event-1", item: %{value: 7}}
             )

    assert first.state.processed_count == 1
    assert agent_result(agent).state_version == 1
  end

  test "invalid input does not consume an event ID and a later valid event works", %{jido: jido} do
    agent = start_agent!(jido, DeduplicatingInbox, error_policy: :log_only)
    before = Jido.AgentServer.snapshot(agent)

    for input <- [%{event_id: "", item: %{}}, %{event_id: "one", item: "invalid"}] do
      assert {:error, _} = DeduplicatingInbox.receive_event(agent, input: input)
      assert Jido.AgentServer.snapshot(agent) == before
    end

    assert {:ok, _} =
             DeduplicatingInbox.receive_event(agent, input: %{event_id: "one", item: %{value: 1}})

    assert {:ok, _} =
             DeduplicatingInbox.receive_event(agent, input: %{event_id: "two", item: %{value: 2}})

    assert agent_result(agent).state.processed_count == 2
  end
end
