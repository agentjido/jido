defmodule JidoTest.Examples.Workflow.EffectfulStepsTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.EffectfulSteps, as: Example
  alias JidoTest.WorkflowService, as: Service

  defp service do
    start_supervised!(
      {Service, %{read: {:ok, %{revision: "r1", answer: "safe", private: "secret"}}}}
    )
  end

  test "caller context reaches the read and only selected output persists", %{jido: jido} do
    client = service()
    persistence = {Jido.Persistence.ETS, table: :"workflow_#{System.unique_integer([:positive])}"}
    server = start_agent!(jido, Example, persistence: persistence, restore: false)
    before = Server.snapshot(server)
    {:ok, command} = Example.fetch_record_signal(%{key: "one"})
    context = %{service: {Service, client}, private_request: make_ref()}

    assert {:ok, candidate, []} = Example.cmd(before.agent, command, context: context)
    assert Server.snapshot(server) == before
    assert {:ok, ^candidate} = Server.call(server, command, context: context)
    assert candidate.state == %{key: "one", result: %{revision: "r1", answer: "safe"}}

    assert {:ok, ^candidate, 1} =
             Jido.Persistence.load_agent_with_revision(persistence, Example, candidate.id,
               instance: jido
             )

    monitor = Process.monitor(server)
    assert :ok = Server.hibernate(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :hibernate}}, 1000
    assert {:ok, restored} = Jido.thaw(jido, Example, candidate.id, persistence: persistence)
    assert Server.snapshot(restored) == %{agent: candidate, state_version: 1}
  end

  test "a guard prevents I/O while a later validation failure cannot undo it", %{jido: jido} do
    client = service()
    server = start_agent!(jido, Example)
    context = %{service: {Service, client}}

    {:ok, route_signal_1} = Example.fetch_record_signal(%{key: "seed"})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_1, context: context)

    before = Server.snapshot(server)

    {:ok, route_signal_2} = Example.fetch_record_signal(%{key: "denied", allowed: false})

    assert {:error, denied} =
             Jido.AgentServer.call(server, route_signal_2, context: context)

    assert Enum.any?(errors(denied), &(&1.message == "request denied"))
    assert Service.calls(client) == [read: %{key: "seed"}]

    {:ok, route_signal_3} =
      Example.fetch_record_signal(%{
        key: "stale",
        allowed: true,
        expected_revision: "r0"
      })

    assert {:error, stale} =
             Jido.AgentServer.call(server, route_signal_3, context: context)

    assert Enum.any?(errors(stale), &(&1.message == "source revision is stale"))

    assert Service.calls(client) == [read: %{key: "seed"}, read: %{key: "stale"}]

    assert Server.snapshot(server) == before
  end

  test "a committed result is cached and caller context does not cross Turns", %{jido: jido} do
    first = service()

    second =
      start_supervised!({Service, %{read: {:ok, %{revision: "r1", answer: "second"}}}},
        id: :second
      )

    server = start_agent!(jido, Example)

    {:ok, route_signal_4} = Example.fetch_record_signal(%{key: "one"})

    assert {:ok, committed} =
             Jido.AgentServer.call(server, route_signal_4, context: %{service: {Service, first}})

    {:ok, route_signal_5} = Example.fetch_record_signal(%{key: "one"})

    assert {:ok, ^committed} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert Service.calls(first) == [read: %{key: "one"}]

    {:ok, route_signal_6} = Example.fetch_record_signal(%{key: "two"})

    assert {:error, error} =
             Jido.AgentServer.call(server, route_signal_6, [])

    assert Enum.any?(errors(error), &(&1.message == "service context required"))

    {:ok, route_signal_7} = Example.fetch_record_signal(%{key: "two"})

    assert {:ok, next} =
             Jido.AgentServer.call(server, route_signal_7, context: %{service: {Service, second}})

    assert next.state.result.answer == "second"
    assert Service.calls(second) == [read: %{key: "two"}]
    assert Server.snapshot(server).state_version == 3
  end
end
