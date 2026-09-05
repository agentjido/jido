defmodule JidoTest.Examples.LLM.GroundedAnswerTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.GroundedAnswer, as: Example

  defp evidence, do: [%{id: "doc", revision: "r2", page: 3, text: "OTP uses processes"}]

  defp answer(cite \\ %{id: "doc", revision: "r2", page: 3}),
    do: %{answer: "processes", citations: [cite]}

  test "retrieval and generation receive exact inputs before validated provenance commits", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    retriever = service([{:ok, evidence()}])
    model = service([{:ok, answer()}])

    assert {:ok, agent} =
             Server.call(server, Example.answer_signal!("OTP?"),
               context: %{retriever: client(retriever), model: client(model)}
             )

    assert calls(retriever) == [{:retrieve, %{query: "OTP?"}}]
    assert calls(model) == [{:complete, %{prompt: "OTP?", evidence: evidence()}}]
    assert agent.state.citations == answer().citations
  end

  test "no evidence makes zero model calls; bad identity, revision, or page cannot replace prior state",
       %{jido: jido} do
    server = start_agent!(jido, Example)

    retriever =
      service([
        {:ok, evidence()},
        {:ok, []},
        {:ok, evidence()},
        {:ok, evidence()},
        {:ok, evidence()}
      ])

    model =
      service([
        {:ok, answer()}
        | Enum.map(
            [
              %{id: "invented", revision: "r2", page: 3},
              %{id: "doc", revision: "r1", page: 3},
              %{id: "doc", revision: "r2", page: 4}
            ],
            &{:ok, answer(&1)}
          )
      ])

    web = service([])
    ctx = %{retriever: client(retriever), model: client(model), web: client(web)}
    assert {:ok, _} = Server.call(server, Example.answer_signal!("seed"), context: ctx)
    before = Server.snapshot(server)
    assert {:error, _} = Server.call(server, Example.answer_signal!("no evidence"), context: ctx)
    assert length(calls(model)) == 1
    assert calls(web) == []

    for prompt <- ["invented", "stale", "wrong page"],
        do:
          assert({:error, _} = Server.call(server, Example.answer_signal!(prompt), context: ctx))

    assert Server.snapshot(server) == before
  end

  test "resolver receives committed history and web search requires explicit permission", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    retriever = service([{:ok, evidence()}, {:ok, []}])
    model = service([{:ok, answer()}, {:ok, answer()}])
    resolver = service([{:ok, %{query: "OTP processes"}}])
    web = service([{:ok, evidence()}])

    ctx = %{
      retriever: client(retriever),
      model: client(model),
      resolver: client(resolver),
      web: client(web)
    }

    assert {:ok, first} = Server.call(server, Example.answer_signal!("OTP?"), context: ctx)
    assert calls(web) == []

    assert {:ok, _} =
             Server.call(
               server,
               Example.answer_signal!("more?", input: %{resolve: true, allow_web: true}),
               context: ctx
             )

    assert calls(resolver) == [{:resolve, %{prompt: "more?", messages: first.state.messages}}]
    assert List.last(calls(retriever)) == {:retrieve, %{query: "OTP processes"}}
    assert calls(web) == [{:search, %{query: "OTP processes"}}]
  end
end
