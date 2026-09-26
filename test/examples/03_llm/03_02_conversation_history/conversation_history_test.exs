defmodule JidoTest.Examples.LLM.ConversationHistoryTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.ConversationHistory, as: Example

  test "two Turns use actual history; duplicates and errors preserve it", %{jido: jido} do
    model = service(ok: %{answer: "A"}, ok: %{answer: "B"}, error: :unavailable)
    server = start_agent!(jido, Example)
    ctx = %{model: client(model)}

    {:ok, command_signal_1} = Example.append_message_signal(%{message_id: "1", text: "first"})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_1,
               context: ctx
             )

    {:ok, command_signal_2} = Example.append_message_signal(%{message_id: "2", text: "second"})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_2,
               context: ctx
             )

    first = [%{role: :user, content: "first"}]
    second = first ++ [%{role: :assistant, content: "A"}, %{role: :user, content: "second"}]
    assert calls(model) == [complete: %{messages: first}, complete: %{messages: second}]
    before = Server.snapshot(server)

    {:ok, command_signal_3} = Example.append_message_signal(%{message_id: "2", text: "duplicate"})

    assert {:error, _} =
             Server.call(
               server,
               command_signal_3,
               context: ctx
             )

    assert length(calls(model)) == 2

    {:ok, command_signal_4} = Example.append_message_signal(%{message_id: "3", text: "fails"})

    assert {:error, _} =
             Server.call(
               server,
               command_signal_4,
               context: ctx
             )

    assert Server.snapshot(server) == before
    assert state(server).processed_ids == ["1", "2"]
  end

  test "persisted history restores and the next Turn uses a fresh client", %{jido: jido} do
    persistence =
      {Jido.Persistence.ETS, table: :"llm_history_#{System.unique_integer([:positive])}"}

    server = start_agent!(jido, Example, persistence: persistence, restore: false)
    old = service(ok: %{answer: "A"})

    {:ok, command_signal_5} = Example.append_message_signal(%{message_id: "1", text: "first"})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_5,
               context: %{model: client(old)}
             )

    ref = Process.monitor(server)
    assert :ok = Server.hibernate(server)
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :hibernate}}, 1000
    assert {:ok, restored} = Jido.thaw(jido, Example, agent.id, persistence: persistence)
    fresh = service(ok: %{answer: "B"})

    {:ok, command_signal_6} = Example.append_message_signal(%{message_id: "2", text: "second"})

    assert {:ok, _} =
             Server.call(
               restored,
               command_signal_6,
               context: %{model: client(fresh)}
             )

    assert calls(fresh) == [
             complete: %{messages: agent.state.messages ++ [%{role: :user, content: "second"}]}
           ]

    assert length(calls(old)) == 1
    assert Server.snapshot(restored).state_version == 2
  end
end
