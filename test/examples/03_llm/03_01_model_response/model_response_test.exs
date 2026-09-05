defmodule JidoTest.Examples.LLM.ModelResponseTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.ModelResponse, as: Example

  test "exact input and selected output cross direct and live boundaries", %{jido: jido} do
    model = service([{:ok, %{answer: "one", private: self()}}, {:ok, %{answer: "one"}}])

    persistence =
      {Jido.Persistence.ETS, table: :"llm_response_#{System.unique_integer([:positive])}"}

    server = start_agent!(jido, Example, persistence: persistence, restore: false)
    before = Server.snapshot(server)
    assert {:ok, signal} = Example.generate_signal("hello")
    assert signal.data == %{prompt: "hello"}

    assert {:ok, candidate, []} =
             Example.cmd(before.agent, signal, context: %{model: client(model)})

    assert Server.snapshot(server) == before
    assert {:ok, ^candidate} = Example.generate(server, "hello", context: %{model: client(model)})
    assert candidate.state == %{answer: "one"}
    assert calls(model) == [{:complete, %{prompt: "hello"}}, {:complete, %{prompt: "hello"}}]

    assert {:ok, ^candidate, 1} =
             Jido.Persistence.load_agent_with_revision(persistence, Example, candidate.id,
               instance: jido
             )
  end

  test "bad input makes no call and bad output preserves a prior commit", %{jido: jido} do
    model = service([{:ok, %{answer: "seed"}}, {:ok, %{answer: []}}])
    server = start_agent!(jido, Example)
    ctx = %{model: client(model)}
    assert {:error, _} = Server.call(server, Example.generate_signal!(""), context: ctx)
    assert calls(model) == []
    assert {:ok, _} = Server.call(server, Example.generate_signal!("seed"), context: ctx)
    before = Server.snapshot(server)
    assert {:error, _} = Server.call(server, Example.generate_signal!("bad"), context: ctx)
    assert Server.snapshot(server) == before
    assert length(calls(model)) == 2
  end

  test "transient fallback records both calls; auth and malformed fallback preserve state", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    primary = service([{:error, :overloaded}, {:error, :unauthorized}, {:error, :timeout}])
    backup = service([{:ok, %{answer: "backup"}}, {:ok, %{answer: nil}}])
    ctx = %{model: client(primary), backup: client(backup)}
    assert {:ok, _} = Server.call(server, Example.generate_signal!("hello"), context: ctx)
    before = Server.snapshot(server)
    assert {:error, _} = Server.call(server, Example.generate_signal!("auth"), context: ctx)
    assert calls(backup) == [{:complete, %{prompt: "hello"}}]
    assert {:error, _} = Server.call(server, Example.generate_signal!("bad backup"), context: ctx)
    assert Server.snapshot(server) == before
    assert Enum.map(calls(primary), &elem(&1, 1).prompt) == ["hello", "auth", "bad backup"]
    assert Enum.map(calls(backup), &elem(&1, 1).prompt) == ["hello", "bad backup"]
  end

  test "execution deadline terminates a blocked provider worker", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [timeout: 200])

    model =
      service([{:ok, %{answer: "seed"}}, blocked(self(), :deadline, {:ok, %{answer: "late"}})])

    assert {:ok, _} =
             Server.call(server, Example.generate_signal!("seed"),
               context: %{model: client(model)}
             )

    before = Server.snapshot(server)

    task =
      Task.async(fn ->
        Server.call(server, Example.generate_signal!("wait"), context: %{model: client(model)})
      end)

    assert_receive {:provider_waiting, :deadline, worker, :complete, %{prompt: "wait"}}, 1_000
    ref = Process.monitor(worker)
    assert {:error, _} = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1_000
    assert Server.snapshot(server) == before
  end
end
