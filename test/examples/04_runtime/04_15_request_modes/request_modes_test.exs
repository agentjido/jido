defmodule JidoTest.Examples.Runtime.RequestModesBlockingAction do
  @moduledoc false
  use Jido.Action,
    name: "test_runtime_request_modes_blocking_action",
    schema: Zoi.object(%{label: Zoi.string() |> Zoi.min(1)})

  alias JidoTest.Examples.RuntimeBarrier

  def run(%{label: label}, context) do
    :ok = RuntimeBarrier.wait()
    {:ok, %{context.agent_state | history: context.agent_state.history ++ [label]}}
  end
end

defmodule JidoTest.Examples.Runtime.RequestModesBlockingAgent do
  @moduledoc false
  use Jido.Agent, name: "test_runtime_request_modes_blocking_agent"

  agent do
    schema Zoi.object(%{history: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/test/examples/runtime/request_modes"

    route "test.examples.runtime.request_modes.record",
          JidoTest.Examples.Runtime.RequestModesBlockingAction
  end
end

defmodule JidoTest.Examples.Runtime.RequestModesTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer
  alias Jido.Examples.RequestModes
  alias JidoTest.Examples.Runtime.RequestModesBlockingAgent
  alias JidoTest.Examples.RuntimeBarrier

  setup do
    start_supervised!(RuntimeBarrier)
    :ok
  end

  test "call, cast, and asynchronous request expose their result contracts", %{jido: jido} do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, RequestModes, id: unique_id("request-modes"))

    {:ok, call_signal} = RequestModes.record_signal(%{label: "call"})
    assert {:ok, called, _directives} = AgentServer.call(server, call_signal)
    assert called.state.history == ["call"]

    {:ok, cast_signal} = RequestModes.record_signal(%{label: "cast"})
    assert :ok = AgentServer.cast(server, cast_signal)

    {:ok, request_signal} = RequestModes.record_signal(%{label: "request"})
    request_id = AgentServer.submit(server, request_signal)
    assert {:ok, requested, []} = AgentServer.await(request_id)
    assert requested.state.history == ["call", "cast", "request"]
  end

  test "several admitted asynchronous requests commit in serial order", %{jido: jido} do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, RequestModes, id: unique_id("request-order"))

    requests =
      for label <- ~w[first second third] do
        {:ok, signal} = RequestModes.record_signal(%{label: label})
        AgentServer.submit(server, signal)
      end

    replies = Enum.map(requests, &AgentServer.await/1)

    assert [
             {:ok, %{state: %{history: ["first"]}}, []},
             {:ok, %{state: %{history: ["first", "second"]}}, []},
             {:ok, %{state: %{history: ["first", "second", "third"]}}, []}
           ] = replies
  end

  test "a caller timeout does not cancel work that already started", %{jido: jido} do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(jido, RequestModesBlockingAgent,
        id: unique_id("request-timeout")
      )

    :ok = RuntimeBarrier.arm(self())

    caller =
      Task.async(fn ->
        signal =
          Jido.Signal.new!(
            "test.examples.runtime.request_modes.record",
            %{label: "completed"},
            source: "/test/examples/runtime/request_modes"
          )

        try do
          AgentServer.call(server, signal, 25)
        catch
          :exit, reason -> {:caller_exit, reason}
        end
      end)

    assert_receive :runtime_barrier_waiting, 1_000
    assert {:caller_exit, _reason} = Task.await(caller)
    assert :ok = RuntimeBarrier.release()

    eventually(fn -> AgentServer.agent(server).state.history == ["completed"] end)
  end

  defp blocked(jido, opts \\ []) do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(
        jido,
        RequestModesBlockingAgent,
        Keyword.put_new(opts, :id, unique_id())
      )

    :ok = RuntimeBarrier.arm(self())
    pending = AgentServer.submit(server, record("active"))
    assert_receive :runtime_barrier_waiting, 1_000
    {server, pending}
  end

  defp record(label),
    do:
      Jido.Signal.new!(
        "test.examples.runtime.request_modes.record",
        %{label: label},
        source: "/test/examples/runtime/request_modes"
      )

  test "capacity rejects excess work and admission expiry leaves no queued work", %{jido: jido} do
    {server, active} = blocked(jido, max_postponed_signals: 1)

    assert {:error, :admission_timeout} =
             AgentServer.call(server, record("expired"), admission_timeout: 0)

    queued = AgentServer.submit(server, record("queued"))
    assert AgentServer.status(server).admission.postponed == 1

    assert {:error, {:overloaded, %{limit: 1, postponed: 1}}} =
             AgentServer.call(server, record("excess"))

    assert :ok = AgentServer.cast(server, record("dropped"))
    assert AgentServer.status(server).admission.postponed == 1
    assert :ok = RuntimeBarrier.release()
    assert {:ok, _, []} = AgentServer.await(active)
    assert {:ok, %{state: %{history: ["active", "queued"]}}, []} = AgentServer.await(queued)
    assert AgentServer.status(server).state_version == 2
  end

  test "await can be repeated after timeout and abandon does not cancel a Turn", %{jido: jido} do
    {server, active} = blocked(jido)
    assert {:error, :timeout} = AgentServer.await(active, 0)
    assert :ok = RuntimeBarrier.release()
    assert {:ok, _, []} = AgentServer.await(active)

    :ok = RuntimeBarrier.arm(self())
    abandoned = AgentServer.submit(server, record("abandoned"))
    assert_receive :runtime_barrier_waiting, 1_000
    assert :ok = AgentServer.abandon(abandoned)
    assert :ok = RuntimeBarrier.release()
    assert :ok = AgentServer.quiesce(server)
    assert AgentServer.agent(server).state.history == ["active", "abandoned"]
  end
end
