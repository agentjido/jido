defmodule JidoTest.Examples.LLM.ContextCompactionTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.ContextCompaction, as: Example

  defp seeded(jido) do
    server = start_agent!(jido, Example)

    for text <- ["keep fact: OTP", "middle", "recent"],
        do: assert({:ok, _} = Server.call(server, Example.append_message_signal!(text)))

    server
  end

  test "compaction reads committed history; queued messages survive and enter the next model input once",
       %{jido: jido} do
    server = seeded(jido)
    before = Server.snapshot(server)

    model =
      service([blocked(self(), :compact, {:ok, %{summary: "OTP"}}), {:ok, %{answer: "reply"}}])

    task =
      Task.async(fn ->
        Server.call(
          server,
          Example.compact_history_signal!(
            input: %{keep: 1, max_bytes: 20, required_facts: ["OTP"]}
          ),
          context: %{model: client(model)}
        )
      end)

    assert_receive {:provider_waiting, :compact, worker, :summarize,
                    %{summary: "", messages: prefix}},
                   1_000

    assert prefix == Enum.take(before.agent.state.messages, 2)
    assert Server.snapshot(server) == before
    assert :ok = Server.cast(server, Example.append_message_signal!("queued"))
    send(worker, {:release, :compact})
    assert {:ok, _} = Task.await(task)

    eventually(fn ->
      state(server).messages == [
        %{role: :user, content: "recent"},
        %{role: :user, content: "queued"}
      ]
    end)

    assert {:ok, _} =
             Server.call(server, Example.reply_signal!("next"), context: %{model: client(model)})

    assert List.last(calls(model)) ==
             {:complete,
              %{
                messages: [
                  %{role: :system, content: "OTP"},
                  %{role: :user, content: "recent"},
                  %{role: :user, content: "queued"},
                  %{role: :user, content: "next"}
                ]
              }}
  end

  test "fact loss, malformed summary, and byte overflow preserve committed messages", %{
    jido: jido
  } do
    server = seeded(jido)
    before = Server.snapshot(server)

    model =
      service([
        {:ok, %{summary: "lost"}},
        {:ok, %{summary: []}},
        {:ok, %{summary: "OTP too large"}}
      ])

    for _ <- 1..3 do
      assert {:error, _} =
               Server.call(
                 server,
                 Example.compact_history_signal!(
                   input: %{keep: 1, max_bytes: 9, required_facts: ["OTP"]}
                 ),
                 context: %{model: client(model)}
               )

      assert Server.snapshot(server) == before
    end

    assert length(calls(model)) == 3
  end
end
