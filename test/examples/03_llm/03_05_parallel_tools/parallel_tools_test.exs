defmodule JidoTest.Examples.LLM.ParallelToolsTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.ParallelTools, as: Example

  defp call(id), do: %{id: id, name: "search", arguments: %{query: id, operation: :read}}

  test "two real workers overlap; reverse completion retains call order", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    model = service(ok: [call("a"), call("b")], ok: %{answer: "done"})
    owner = self()

    tools =
      service(
        Enum.map(1..2, fn _ ->
          fn operation, input ->
            blocked(owner, input.query, {:ok, input.query}).(operation, input)
          end
        end)
      )

    task =
      Task.async(fn ->
        {:ok, command_signal_1} = Example.plan_signal(%{prompt: "parallel"})

        Server.call(
          server,
          command_signal_1,
          context: %{model: client(model), tools: client(tools)}
        )
      end)

    assert_receive {:provider_waiting, "a", a, :search, _}, 1000
    assert_receive {:provider_waiting, "b", b, :search, _}, 1000
    assert a != b
    assert Server.snapshot(server).state_version == 0
    ref_b = Process.monitor(b)
    send(b, {:release, "b"})
    assert_receive {:DOWN, ^ref_b, :process, ^b, _}, 1000
    send(a, {:release, "a"})
    assert {:ok, agent} = Task.await(task)
    results = [%{id: "a", result: "a"}, %{id: "b", result: "b"}]
    assert agent.state.tool_results == results
    assert List.last(calls(model)) == {:finish, %{prompt: "parallel", results: results}}
  end

  test "a finite plan obeys the serial limit", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 1])
    model = service(ok: [call("a"), call("b")], ok: %{answer: "done"})
    tools = service([blocked(self(), :a, {:ok, "a"}), blocked(self(), :b, {:ok, "b"})])

    task =
      Task.async(fn ->
        {:ok, command_signal_2} = Example.plan_signal(%{prompt: "serial"})

        Server.call(
          server,
          command_signal_2,
          context: %{model: client(model), tools: client(tools)}
        )
      end)

    assert_receive {:provider_waiting, :a, a, _, _}, 1000
    assert length(calls(tools)) == 1
    refute_received {:provider_waiting, :b, _, _, _}
    send(a, {:release, :a})
    assert_receive {:provider_waiting, :b, b, _, _}, 1000
    send(b, {:release, :b})
    assert {:ok, _} = Task.await(task)
  end

  test "complete plan admission rejects duplicate IDs, unknown names, and bad arguments before any effect",
       %{jido: jido} do
    server = start_agent!(jido, Example)
    tools = service([])

    for plan <- [
          [call("a"), call("a")],
          [call("a"), %{call("b") | name: "unknown"}],
          [call("a"), %{call("b") | arguments: %{query: 12, operation: :read}}]
        ] do
      model = service(ok: plan)

      {:ok, command_signal_3} = Example.plan_signal(%{prompt: "invalid plan"})

      assert {:error, _} =
               Server.call(
                 server,
                 command_signal_3,
                 context: %{model: client(model), tools: client(tools)}
               )
    end

    assert calls(tools) == []
  end

  test "empty tools and collected item errors reach the model with stable correlation", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    model =
      service(
        ok: [],
        ok: %{answer: "no tools"},
        ok: [call("a")],
        ok: %{answer: "tool unavailable"}
      )

    tools = service(error: :unavailable)
    ctx = %{model: client(model), tools: client(tools)}

    {:ok, command_signal_4} = Example.plan_signal(%{prompt: "empty"})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_4,
               context: ctx
             )

    assert calls(tools) == []
    assert List.last(calls(model)) == {:finish, %{prompt: "empty", results: []}}

    {:ok, command_signal_5} = Example.plan_signal(%{prompt: "error"})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_5,
               context: ctx
             )

    assert [%{id: "a", error: _}] = agent.state.tool_results

    assert List.last(calls(model)) ==
             {:finish, %{prompt: "error", results: agent.state.tool_results}}
  end

  test "cancellation terminates all active tools and preserves a prior commit", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    model = service(ok: [], ok: %{answer: "seed"}, ok: [call("a"), call("b")])
    tools = service([blocked(self(), :first, {:ok, "a"}), blocked(self(), :second, {:ok, "b"})])
    ctx = %{model: client(model), tools: client(tools)}

    {:ok, command_signal_6} = Example.plan_signal(%{prompt: "seed"})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_6,
               context: ctx
             )

    before = Server.snapshot(server)

    task =
      Task.async(fn ->
        {:ok, command_signal_7} = Example.plan_signal(%{prompt: "cancel"})

        Server.call(
          server,
          command_signal_7,
          context: ctx
        )
      end)

    assert_receive {:provider_waiting, :first, a, _, _}, 1000
    assert_receive {:provider_waiting, :second, b, _, _}, 1000
    refs = Enum.map([a, b], &{&1, Process.monitor(&1)})
    assert :ok = Server.cancel(server)
    assert {:error, _} = Task.await(task)

    for {worker, ref} <- refs do
      assert_receive({:DOWN, ^ref, :process, ^worker, _}, 1000)
    end

    assert Server.snapshot(server) == before
  end
end
