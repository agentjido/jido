Code.require_file("read_service.ex", __DIR__)
Code.require_file("effectful_steps.ex", __DIR__)

defmodule Jido.Examples.Workflow.EffectfulStepsTest do
  use Jido.Test.Agent.WorkflowSDKCase
  @moduletag :integration

  alias Jido.Examples.EffectfulSteps, as: Example
  alias Jido.Examples.EffectfulSteps.ReadService, as: Service

  defp service do
    start_supervised!({Service, %{read: {:ok, %{revision: "r1", answer: "safe", private: "secret"}}}})
  end

  test "portable service context stays outside committed Agent state", c do
    client = service()
    persistence = {Jido.Persistence.ETS, table: :"workflow_#{System.unique_integer([:positive])}"}
    %{jido: jido} = restart_jido!(c, persistence)
    server = start_agent!(jido, Example, persistence_mode: :create)
    before = Jido.AgentServer.snapshot(server)
    {:ok, command} = Example.fetch_record_signal(%{key: "one"})
    service_name = Module.concat(__MODULE__, ReadService)
    Process.register(client, service_name)
    context = %{service: {Service, service_name}, private_request: "request-1"}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _}} =
             Jido.AgentServer.call(server, command, context: %{service: {Service, client}, private_request: make_ref()})

    assert Service.calls(client) == []
    assert Jido.AgentServer.snapshot(server) == before

    assert {:ok, candidate, []} = Example.cmd(before.agent, command, context: context)
    assert Jido.AgentServer.snapshot(server) == before

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, command, context: context)

      assert turn_result.status in [:committed, :waiting]
      assert candidate == Jido.AgentServer.snapshot(server).agent
    )

    assert candidate.state == %{key: "one", result: %{revision: "r1", answer: "safe"}}

    assert {:ok, ^candidate, 2} =
             Jido.Persistence.load_agent_with_revision(persistence, Example, candidate.id, instance: jido)

    monitor = Process.monitor(server)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, :shutdown}, 1000
    assert {:ok, restored} = Jido.thaw(jido, Example, candidate.id)
    assert :ok = Jido.AgentServer.await_ready(restored)
    assert Jido.AgentServer.snapshot(restored).agent.state == candidate.state
    assert Jido.AgentServer.snapshot(restored).agent_revision == 1
  end

  test "a guard prevents I/O while a later validation failure cannot undo it", %{jido: jido} do
    client = service()
    server = start_agent!(jido, Example)
    context = %{service: {Service, client}}

    {:ok, route_signal_1} = Example.fetch_record_signal(%{key: "seed"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_1, context: context)

      assert turn_result.status in [:committed, :waiting]
    )

    before = Jido.AgentServer.snapshot(server)

    {:ok, route_signal_2} = Example.fetch_record_signal(%{key: "denied", allowed: false})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: denied}} =
             Jido.AgentServer.call(server, route_signal_2, context: context)

    assert Enum.any?(errors(denied), &(&1.message == "request denied"))
    assert Service.calls(client) == [read: %{key: "seed"}]

    {:ok, route_signal_3} =
      Example.fetch_record_signal(%{
        key: "stale",
        allowed: true,
        expected_revision: "r0"
      })

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: stale}} =
             Jido.AgentServer.call(server, route_signal_3, context: context)

    assert Enum.any?(errors(stale), &(&1.message == "source revision is stale"))

    assert Service.calls(client) == [read: %{key: "seed"}, read: %{key: "stale"}]

    assert Jido.AgentServer.snapshot(server) == before
  end

  test "a committed result is cached and caller context does not cross Turns", %{jido: jido} do
    first = service()

    second =
      start_supervised!({Service, %{read: {:ok, %{revision: "r1", answer: "second"}}}},
        id: :second
      )

    server = start_agent!(jido, Example)

    {:ok, route_signal_4} = Example.fetch_record_signal(%{key: "one"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_4, context: %{service: {Service, first}})

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    {:ok, route_signal_5} = Example.fetch_record_signal(%{key: "one"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_5, [])

      assert turn_result.status in [:committed, :waiting]
      assert committed == Jido.AgentServer.snapshot(server).agent
    )

    assert Service.calls(first) == [read: %{key: "one"}]

    {:ok, route_signal_6} = Example.fetch_record_signal(%{key: "two"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             Jido.AgentServer.call(server, route_signal_6, [])

    assert Enum.any?(errors(error), &(&1.message == "service context required"))

    {:ok, route_signal_7} = Example.fetch_record_signal(%{key: "two"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_7, context: %{service: {Service, second}})

      assert turn_result.status in [:committed, :waiting]
      next = Jido.AgentServer.snapshot(server).agent
    )

    assert next.state.result.answer == "second"
    assert Service.calls(second) == [read: %{key: "two"}]
    assert Jido.AgentServer.snapshot(server).agent_revision == 3
  end

  test "bounded retries repeat the read and commit the Agent only once", %{jido: jido} do
    client =
      start_supervised!(
        {Service,
         %{
           read: [
             {:error, :unavailable},
             {:ok, %{revision: "r1", answer: "recovered"}}
           ]
         }}
      )

    server = start_agent!(jido, Example, exec_opts: [max_attempts: 2, backoff: :none])
    {:ok, command} = Example.fetch_record_signal(%{key: "retry"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, command, context: %{service: {Service, client}})

      assert turn_result.status in [:committed, :waiting]
      %{state: %{result: %{answer: "recovered"}}} = Jido.AgentServer.snapshot(server).agent
    )

    assert Service.calls(client) == [read: %{key: "retry"}, read: %{key: "retry"}]
    assert Jido.AgentServer.snapshot(server).agent_revision == 1
  end

  test "retry exhaustion preserves the previous Agent commit", %{jido: jido} do
    client = start_supervised!({Service, %{read: {:error, :unavailable}}})
    server = start_agent!(jido, Example, exec_opts: [max_attempts: 2, backoff: :none])
    before = Jido.AgentServer.snapshot(server)
    {:ok, command} = Example.fetch_record_signal(%{key: "retry"})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _}} =
             Jido.AgentServer.call(server, command, context: %{service: {Service, client}})

    assert length(Service.calls(client)) == 2
    assert Jido.AgentServer.snapshot(server) == before
  end
end
