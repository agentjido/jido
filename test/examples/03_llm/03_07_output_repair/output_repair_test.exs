defmodule JidoTest.Examples.LLM.OutputRepairTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.OutputRepair, as: Example

  test "valid first output makes one call and invalid output sends specific feedback", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    model =
      service([{:ok, %{answer: "first"}}, {:ok, %{answer: []}}, {:ok, %{answer: "repaired"}}])

    ctx = %{model: client(model)}
    assert {:ok, agent} = Server.call(server, Example.answer_signal!("valid"), context: ctx)
    assert agent.state == %{answer: "first", attempts: 1}
    assert calls(model) == [{:complete, %{prompt: "valid", feedback: "", attempt: 1}}]
    assert {:ok, agent} = Server.call(server, Example.answer_signal!("repair"), context: ctx)
    assert agent.state == %{answer: "repaired", attempts: 2}

    assert {:complete, %{attempt: 2, feedback: feedback, prompt: "repair"}} =
             List.last(calls(model))

    assert feedback =~ "answer"
    assert feedback != ""
  end

  test "last allowed repair succeeds; exhaustion makes exactly three calls and preserves it", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    model =
      service([
        {:ok, %{}},
        {:ok, %{}},
        {:ok, %{answer: "last"}},
        {:ok, %{}},
        {:ok, %{}},
        {:ok, %{}},
        {:ok, %{answer: "must not run"}}
      ])

    ctx = %{model: client(model)}
    assert {:ok, agent} = Server.call(server, Example.answer_signal!("last repair"), context: ctx)
    assert agent.state.attempts == 3
    before = Server.snapshot(server)
    assert {:error, _} = Server.call(server, Example.answer_signal!("exhaust"), context: ctx)
    assert Server.snapshot(server) == before
    assert Enum.map(calls(model), &elem(&1, 1).attempt) == [1, 2, 3, 1, 2, 3]
  end

  test "provider failure is not an automatic repair", %{jido: jido} do
    server = start_agent!(jido, Example)
    model = service([{:error, :unauthorized}, {:ok, %{answer: "must not run"}}])

    assert {:error, _} =
             Server.call(server, Example.answer_signal!("fail"), context: %{model: client(model)})

    assert length(calls(model)) == 1
  end
end
