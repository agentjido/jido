defmodule JidoTest.Examples.LLM.SubagentDelegationTest do
  use JidoTest.LLMSDKCase
  alias Jido.Examples.LLM.Adapter
  alias Jido.Examples.LLMSubagentDelegation, as: Example

  defp plan(role \\ "researcher"), do: {:ok, %{role: role, prompt: "Find evidence"}}

  defp reply(id, answer),
    do:
      Adapter.signal("delegate.result", %{
        request_id: id,
        tag: id,
        status: :complete,
        answer: answer,
        error: ""
      })

  test "portable Directives start a real child; independent model work follows the pending commit",
       %{jido: jido} do
    server = start_agent!(jido, Example)
    model = service([plan(), plan()])
    specialist = service([blocked(self(), :child, {:ok, %{answer: "evidence"}})])
    ctx = %{model: client(model), specialist: client(specialist)}
    signal = Example.delegate_signal!("req-1", "research OTP")
    before = Server.snapshot(server)
    assert {:ok, candidate, [spawn, work]} = Example.cmd(before.agent, signal, context: ctx)
    assert %Jido.Agent.Directive.SpawnAgent{tag: "req-1", agent: Example.Specialist} = spawn

    assert Map.from_struct(work) == %{
             request_id: "req-1",
             tag: "req-1",
             role: "researcher",
             prompt: "Find evidence"
           }

    assert candidate.state.status == :working
    assert Server.children(server) == %{}
    task = Task.async(fn -> Server.call(server, signal, context: ctx) end)

    assert_receive {:provider_waiting, :child, worker, :complete,
                    %{role: "researcher", prompt: "Find evidence"}},
                   1_000

    assert state(server).status == :working
    assert state(server).results == []
    assert %{"req-1" => child} = Server.children(server)
    assert child.pid != server
    assert Server.snapshot(child.pid).state_version == 0
    monitor = Process.monitor(child.pid)
    send(worker, {:release, :child})
    assert {:ok, pending} = Task.await(task)
    assert pending.state.status == :working
    eventually(fn -> state(server).status == :complete end)
    assert [%{request_id: "req-1", answer: "evidence", status: :complete}] = state(server).results
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    eventually(fn -> Server.children(server) == %{} end)
    assert calls(specialist) == [{:complete, %{role: "researcher", prompt: "Find evidence"}}]

    assert calls(model) == [
             {:delegate, %{prompt: "research OTP"}},
             {:delegate, %{prompt: "research OTP"}}
           ]
  end

  test "stale and duplicate results cannot complete another request; duplicate IDs make no model call",
       %{jido: jido} do
    server = start_agent!(jido, Example)
    model = service([plan(), plan("reviewer")])

    specialist =
      service([{:ok, %{answer: "first"}}, blocked(self(), :second, {:ok, %{answer: "second"}})])

    ctx = %{model: client(model), specialist: client(specialist)}
    assert {:ok, _} = Server.call(server, Example.delegate_signal!("one", "first"), context: ctx)
    eventually(fn -> state(server).status == :complete end)

    task =
      Task.async(fn ->
        Server.call(server, Example.delegate_signal!("two", "review"), context: ctx)
      end)

    assert_receive {:provider_waiting, :second, worker, _, %{role: "reviewer"}}, 1_000
    assert :ok = Server.cast(server, reply("one", "stale"))

    assert :ok =
             Server.cast(
               server,
               Adapter.signal("delegate.result", %{
                 request_id: "two",
                 tag: "wrong-child",
                 status: :complete,
                 answer: "wrong",
                 error: ""
               })
             )

    send(worker, {:release, :second})
    assert {:ok, _} = Task.await(task)
    eventually(fn -> length(state(server).results) == 2 end)
    assert Enum.map(state(server).results, & &1.answer) == ["first", "second"]
    assert {:ok, _} = Server.call(server, reply("two", "duplicate"))

    assert {:error, _} =
             Server.call(server, Example.delegate_signal!("two", "duplicate request"),
               context: ctx
             )

    assert length(state(server).results) == 2
    assert length(calls(model)) == 2
    assert length(calls(specialist)) == 2
  end

  test "invalid specialist selection starts no child and performs no specialist effect", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    model = service([plan("Elixir.System")])
    specialist = service([])

    assert {:error, _} =
             Server.call(server, Example.delegate_signal!("bad", "bad role"),
               context: %{model: client(model), specialist: client(specialist)}
             )

    assert calls(specialist) == []
    assert Server.children(server) == %{}
    assert Server.snapshot(server).state_version == 0
  end

  test "child model failure becomes a correlated result and a new request can succeed", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    model = service([plan(), plan(), plan()])

    specialist =
      service([{:ok, %{answer: "seed"}}, {:ok, %{answer: []}}, {:ok, %{answer: "retry"}}])

    ctx = %{model: client(model), specialist: client(specialist)}
    assert {:ok, _} = Server.call(server, Example.delegate_signal!("seed", "seed"), context: ctx)
    eventually(fn -> state(server).status == :complete end)
    first = hd(state(server).results)

    assert {:ok, _} =
             Server.call(server, Example.delegate_signal!("bad", "bad answer"), context: ctx)

    eventually(fn -> state(server).status == :failed end)
    assert [^first, %{request_id: "bad", status: :failed, error: reason}] = state(server).results
    assert reason =~ "invalid model data"
    eventually(fn -> Server.children(server) == %{} end)

    assert {:ok, _} =
             Server.call(server, Example.delegate_signal!("retry", "try again"), context: ctx)

    eventually(fn -> state(server).status == :complete end)
    assert List.last(state(server).results).answer == "retry"
  end

  test "child process loss cannot leave the parent request pending", %{jido: jido} do
    server = start_agent!(jido, Example)
    model = service([plan()])
    specialist = service([blocked(self(), :crash, {:ok, %{answer: "unreachable"}})])

    task =
      Task.async(fn ->
        Server.call(server, Example.delegate_signal!("crash", "work"),
          context: %{model: client(model), specialist: client(specialist)}
        )
      end)

    assert_receive {:provider_waiting, :crash, worker, _, _}, 1_000
    assert %{"crash" => child} = Server.children(server)
    monitor = Process.monitor(worker)
    Process.exit(child.pid, :kill)
    assert {:ok, _} = Task.await(task)
    eventually(fn -> state(server).status == :failed end)
    assert [%{request_id: "crash", status: :failed}] = state(server).results
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    eventually(fn -> Server.children(server) == %{} end)
  end

  test "the child's execution deadline ends blocked model work and reports failure", %{jido: jido} do
    server = start_agent!(jido, Example)
    model = service([plan()])
    specialist = service([blocked(self(), :deadline, {:ok, %{answer: "late"}})])

    task =
      Task.async(fn ->
        Server.call(server, Example.delegate_signal!("deadline", "wait"),
          context: %{model: client(model), specialist: client(specialist)}
        )
      end)

    assert_receive {:provider_waiting, :deadline, worker, _, _}, 1_000
    monitor = Process.monitor(worker)
    assert {:ok, _} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    eventually(fn -> state(server).status == :failed end)
    assert [%{request_id: "deadline", status: :failed, error: reason}] = state(server).results
    assert reason =~ "timeout"
    eventually(fn -> Server.children(server) == %{} end)
  end
end
