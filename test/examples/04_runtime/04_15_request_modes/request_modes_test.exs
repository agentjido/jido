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
    {:ok, server} = Jido.start_agent(jido, RequestModes, id: unique_id("request-modes"))

    {:ok, call_signal} = RequestModes.record_signal(%{label: "call"})
    assert {:ok, called} = AgentServer.call(server, call_signal)
    assert called.state.history == ["call"]

    {:ok, cast_signal} = RequestModes.record_signal(%{label: "cast"})
    assert :ok = AgentServer.cast(server, cast_signal)

    {:ok, request_signal} = RequestModes.record_signal(%{label: "request"})
    request_id = AgentServer.send_request(server, request_signal)
    assert {:reply, {:ok, requested}} = AgentServer.receive_response(request_id)
    assert requested.state.history == ["call", "cast", "request"]
  end

  test "several admitted asynchronous requests commit in serial order", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, RequestModes, id: unique_id("request-order"))

    requests =
      for label <- ~w[first second third] do
        {:ok, signal} = RequestModes.record_signal(%{label: label})
        AgentServer.send_request(server, signal)
      end

    replies = Enum.map(requests, &AgentServer.receive_response/1)

    assert [
             {:reply, {:ok, %{state: %{history: ["first"]}}}},
             {:reply, {:ok, %{state: %{history: ["first", "second"]}}}},
             {:reply, {:ok, %{state: %{history: ["first", "second", "third"]}}}}
           ] = replies
  end

  test "a caller timeout does not cancel work that already started", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, RequestModesBlockingAgent, id: unique_id("request-timeout"))

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
end
