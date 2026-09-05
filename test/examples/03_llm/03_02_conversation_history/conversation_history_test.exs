defmodule JidoTest.Examples.LLM.ConversationHistoryTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.ConversationHistory, as: Example

  test "two Turns use actual history; duplicates and errors preserve it", %{jido: jido} do
    model = service([{:ok, %{answer: "A"}}, {:ok, %{answer: "B"}}, {:error, :unavailable}])
    server = start_agent!(jido, Example)
    ctx = %{model: client(model)}

    assert {:ok, _} =
             Server.call(server, Example.append_message_signal!("1", "first"), context: ctx)

    assert {:ok, _} =
             Server.call(server, Example.append_message_signal!("2", "second"), context: ctx)

    first = [%{role: :user, content: "first"}]
    second = first ++ [%{role: :assistant, content: "A"}, %{role: :user, content: "second"}]
    assert calls(model) == [{:complete, %{messages: first}}, {:complete, %{messages: second}}]
    before = Server.snapshot(server)

    assert {:error, _} =
             Server.call(server, Example.append_message_signal!("2", "duplicate"), context: ctx)

    assert length(calls(model)) == 2

    assert {:error, _} =
             Server.call(server, Example.append_message_signal!("3", "fails"), context: ctx)

    assert Server.snapshot(server) == before
    assert state(server).processed_ids == ["1", "2"]
  end

  test "persisted history restores and the next Turn uses a fresh client", %{jido: jido} do
    persistence =
      {Jido.Persistence.ETS, table: :"llm_history_#{System.unique_integer([:positive])}"}

    server = start_agent!(jido, Example, persistence: persistence, restore: false)
    old = service([{:ok, %{answer: "A"}}])

    assert {:ok, agent} =
             Server.call(server, Example.append_message_signal!("1", "first"),
               context: %{model: client(old)}
             )

    ref = Process.monitor(server)
    assert :ok = Server.hibernate(server)
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :hibernate}}, 1_000
    assert {:ok, restored} = Jido.thaw(jido, Example, agent.id, persistence: persistence)
    fresh = service([{:ok, %{answer: "B"}}])

    assert {:ok, _} =
             Server.call(restored, Example.append_message_signal!("2", "second"),
               context: %{model: client(fresh)}
             )

    assert calls(fresh) == [
             {:complete, %{messages: agent.state.messages ++ [%{role: :user, content: "second"}]}}
           ]

    assert length(calls(old)) == 1
    assert Server.snapshot(restored).state_version == 2
  end
end
