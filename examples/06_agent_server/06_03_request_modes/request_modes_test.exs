Code.require_file("request_modes.ex", __DIR__)

defmodule Jido.Test.Examples.Runtime.RequestModesBlockingAction do
  @moduledoc false
  use Jido.Action,
    name: "test_runtime_request_modes_blocking_action",
    schema: Jido.Joi.object(%{label: Jido.Joi.string() |> Jido.Joi.min(1)})

  alias Jido.Test.AgentServer.RuntimeBarrier

  def run(%{label: label}, context) do
    :ok = RuntimeBarrier.wait()
    {:ok, %{context.agent_state | history: context.agent_state.history ++ [label]}}
  end
end

defmodule Jido.Test.Examples.Runtime.RequestModesBlockingAgent do
  @moduledoc false
  use Jido.Agent, name: "test_runtime_request_modes_blocking_agent"

  state do
    schema Jido.Joi.object(%{history: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/test/examples/runtime/request_modes"

    route "test.examples.runtime.request_modes.record",
          Jido.Test.Examples.Runtime.RequestModesBlockingAction do
    end
  end
end

defmodule Jido.Examples.Runtime.RequestModesTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.Examples.RequestModes
  alias Jido.Test.Examples.Runtime.RequestModesBlockingAgent
  alias Jido.Test.AgentServer.RuntimeBarrier

  setup do
    start_supervised!(RuntimeBarrier)
    :ok
  end

  test "call, cast, and asynchronous request expose their result contracts", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, RequestModes, id: unique_id("request-modes"))

    {:ok, call_signal} = RequestModes.record_signal(%{label: "call"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, call_signal)

      assert turn_result.status in [:committed, :waiting]
      called = Jido.AgentServer.snapshot(server).agent
    )

    assert called.state.history == ["call"]

    {:ok, cast_signal} = RequestModes.record_signal(%{label: "cast"})
    assert :ok = Jido.AgentServer.cast(server, cast_signal)

    {:ok, request_signal} = RequestModes.record_signal(%{label: "request"})
    pending = Jido.AgentServer.submit(server, request_signal)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, agent_revision: 3}} =
             Jido.AgentServer.await(pending)

    assert Jido.AgentServer.snapshot(server).agent.state.history == ["call", "cast", "request"]
  end

  test "several admitted asynchronous requests commit in serial order", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, RequestModes, id: unique_id("request-order"))

    requests =
      for label <- ~w[first second third] do
        {:ok, signal} = RequestModes.record_signal(%{label: label})
        Jido.AgentServer.submit(server, signal)
      end

    results = Enum.map(requests, &Jido.AgentServer.await/1)

    assert Enum.map(results, fn {:ok, result} -> {result.status, result.agent_revision} end) ==
             [{:committed, 1}, {:committed, 2}, {:committed, 3}]

    assert Jido.AgentServer.snapshot(server).agent.state.history == ["first", "second", "third"]
  end

  test "a caller timeout does not cancel work that already started", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, RequestModesBlockingAgent,
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
          Jido.AgentServer.call(server, signal, 25)
        catch
          :exit, reason -> {:caller_exit, reason}
        end
      end)

    assert_receive :runtime_barrier_waiting, 1_000
    assert {:caller_exit, _reason} = Task.await(caller)
    assert :ok = RuntimeBarrier.release()

    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.history == ["completed"] end)
  end

  defp blocked(jido, opts \\ []) do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(
        jido,
        RequestModesBlockingAgent,
        Keyword.put_new(opts, :id, unique_id())
      )

    :ok = RuntimeBarrier.arm(self())
    pending = Jido.AgentServer.submit(server, record("active"))
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
             Jido.AgentServer.call(server, record("expired"), admission_timeout: 0)

    queued = Jido.AgentServer.submit(server, record("queued"))
    assert Jido.AgentServer.status(server).queue_depth == 1

    assert {:error, {:overloaded, %{limit: 1, postponed: 1}}} =
             Jido.AgentServer.call(server, record("excess"))

    assert :ok = Jido.AgentServer.cast(server, record("dropped"))
    assert Jido.AgentServer.status(server).queue_depth == 1
    assert :ok = RuntimeBarrier.release()

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, agent_revision: 1}} =
             Jido.AgentServer.await(active)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, agent_revision: 2}} =
             Jido.AgentServer.await(queued)

    assert Jido.AgentServer.status(server).agent_revision == 2
  end

  test "await can be repeated after timeout and abandon does not cancel a Turn", %{jido: jido} do
    {server, active} = blocked(jido)
    assert {:error, :timeout} = Jido.AgentServer.await(active, 0)
    assert :ok = RuntimeBarrier.release()

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.await(active)

    :ok = RuntimeBarrier.arm(self())
    abandoned = Jido.AgentServer.submit(server, record("abandoned"))
    assert_receive :runtime_barrier_waiting, 1_000
    assert :ok = Jido.AgentServer.abandon(abandoned)
    assert :ok = RuntimeBarrier.release()

    assert {:ok, %Jido.AgentServer.Status{admission: :quiesced}} =
             Jido.AgentServer.quiesce(server)

    assert Jido.AgentServer.snapshot(server).agent.state.history == ["active", "abandoned"]
  end
end
