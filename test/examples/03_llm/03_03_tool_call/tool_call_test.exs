defmodule JidoTest.Examples.LLM.ToolCallTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.ToolCall, as: Example

  defp selected(overrides \\ %{}),
    do:
      Map.merge(
        %{id: "call-1", name: "search", arguments: %{query: "OTP", operation: :read}},
        overrides
      )

  test "a typed tool result retains its call ID in the final model input", %{jido: jido} do
    model = service(ok: selected(), ok: %{answer: "answer"})
    tools = service(ok: "evidence")
    server = start_agent!(jido, Example)

    {:ok, command_signal_1} = Example.ask_signal(%{prompt: "question"})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_1,
               context: %{model: client(model), tools: client(tools)}
             )

    results = [%{id: "call-1", result: "evidence"}]
    assert agent.state == %{answer: "answer", tool_results: results}

    assert calls(model) == [
             select: %{prompt: "question"},
             finish: %{prompt: "question", results: results}
           ]

    assert calls(tools) == [search: %{query: "OTP", operation: :read}]
    assert Server.snapshot(server).state_version == 1
  end

  test "unknown tools, bad arguments, and denied operations make zero tool calls", %{jido: jido} do
    tools = service([])
    server = start_agent!(jido, Example)

    for call <- [
          selected(%{name: "Elixir.System"}),
          selected(%{arguments: %{query: [], operation: :read}}),
          selected(%{arguments: %{query: "OTP", operation: :delete}})
        ] do
      model = service(ok: call)

      {:ok, command_signal_2} = Example.ask_signal(%{prompt: "bad"})

      assert {:error, _} =
               Server.call(
                 server,
                 command_signal_2,
                 context: %{model: client(model), tools: client(tools)}
               )

      assert length(calls(model)) == 1
    end

    assert calls(tools) == []
    assert Server.snapshot(server).state_version == 0
  end

  test "SDK tool schema prevents direct invalid execution", %{jido: jido} do
    tools = service([])

    assert {:error, _} =
             Jido.Exec.run(
               Jido.Examples.LLM.SearchTool,
               %{id: "x", query: [], operation: :read},
               %{tools: client(tools)},
               task_supervisor: Jido.task_supervisor_name(jido)
             )

    assert calls(tools) == []
  end

  test "tool failure and late answer failure preserve prior state but keep external effects", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    model =
      service(
        ok: selected(),
        ok: %{answer: "seed"},
        ok: selected(),
        ok: selected(),
        ok: %{answer: []}
      )

    tools = service(ok: "seed", error: :unavailable, ok: "effect remains")
    ctx = %{model: client(model), tools: client(tools)}

    {:ok, command_signal_3} = Example.ask_signal(%{prompt: "seed"})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_3,
               context: ctx
             )

    before = Server.snapshot(server)

    {:ok, command_signal_4} = Example.ask_signal(%{prompt: "tool error"})

    assert {:error, _} =
             Server.call(
               server,
               command_signal_4,
               context: ctx
             )

    {:ok, command_signal_5} = Example.ask_signal(%{prompt: "answer error"})

    assert {:error, _} =
             Server.call(
               server,
               command_signal_5,
               context: ctx
             )

    assert Server.snapshot(server) == before
    assert length(calls(tools)) == 3

    assert {:finish, %{results: [%{id: "call-1", result: "effect remains"}]}} =
             List.last(calls(model))
  end
end
