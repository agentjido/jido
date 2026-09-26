defmodule JidoTest.Examples.LLM.OutputRepairTest do
  use JidoTest.LLMSDKCase

  alias Jido.Examples.OutputRepair, as: Example

  test "valid first output makes one call and invalid output sends specific feedback", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    model =
      service(ok: %{answer: "first"}, ok: %{answer: []}, ok: %{answer: "repaired"})

    context = %{model: client(model)}

    {:ok, command_signal_1} = Example.answer_signal(%{prompt: "valid"})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_1,
               context: context
             )

    assert agent.state == %{answer: "first", attempts: 1}
    assert calls(model) == [complete: %{prompt: "valid", feedback: "", attempt: 1}]

    {:ok, command_signal_2} = Example.answer_signal(%{prompt: "repair"})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_2,
               context: context
             )

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
      service(
        ok: %{},
        ok: %{},
        ok: %{answer: "last"},
        ok: %{},
        ok: %{},
        ok: %{},
        ok: %{answer: "must not run"}
      )

    context = %{model: client(model)}

    {:ok, command_signal_3} = Example.answer_signal(%{prompt: "last repair"})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_3,
               context: context
             )

    assert agent.state.attempts == 3
    before = Server.snapshot(server)

    {:ok, command_signal_4} = Example.answer_signal(%{prompt: "exhaust"})

    assert {:error, _} =
             Server.call(
               server,
               command_signal_4,
               context: context
             )

    assert Server.snapshot(server) == before
    assert Enum.map(calls(model), &elem(&1, 1).attempt) == [1, 2, 3, 1, 2, 3]
  end

  test "provider failure is not an automatic repair", %{jido: jido} do
    server = start_agent!(jido, Example)
    model = service(error: :unauthorized, ok: %{answer: "must not run"})

    {:ok, command_signal_5} = Example.answer_signal(%{prompt: "fail"})

    assert {:error, _} =
             Server.call(
               server,
               command_signal_5,
               context: %{model: client(model)}
             )

    assert length(calls(model)) == 1
  end
end
