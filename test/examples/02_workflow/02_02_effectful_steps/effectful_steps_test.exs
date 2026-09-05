defmodule JidoTest.Examples.Workflow.EffectfulStepsTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.EffectfulSteps, as: Example
  alias JidoTest.WorkflowService, as: Service

  defp service do
    start_supervised!(
      {Service, %{read: {:ok, %{revision: "r1", answer: "safe", private: "secret"}}}}
    )
  end

  test "caller context reaches Flow steps and only selected output persists and restores", %{
    jido: jido
  } do
    client = service()
    persistence = {Jido.Persistence.ETS, table: :"workflow_#{System.unique_integer([:positive])}"}
    server = start_agent!(jido, Example, persistence: persistence, restore: false)
    before = Server.snapshot(server)
    command = Example.fetch_record_signal!("one")
    ctx = context([], %{service: {Service, client}, private_request: make_ref()})
    assert command.data == %{key: "one"}
    assert {:ok, candidate, []} = Example.cmd(before.agent, command, context: ctx)
    assert Server.snapshot(server) == before
    assert {:ok, ^candidate} = Server.call(server, command, context: ctx)
    assert candidate.state == %{key: "one", result: %{revision: "r1", answer: "safe"}}
    assert length(Service.calls(client)) == 2

    assert {:ok, ^candidate, 1} =
             Jido.Persistence.load_agent_with_revision(persistence, Example, candidate.id,
               instance: jido
             )

    monitor = Process.monitor(server)
    assert :ok = Server.hibernate(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, :hibernate}}, 1_000

    assert {:ok, restored} =
             Jido.thaw(jido, Example, candidate.id, persistence: persistence)

    assert Server.snapshot(restored) == %{agent: candidate, state_version: 1}
  end

  test "guard rejection prevents the call while late rejection cannot undo it", %{jido: jido} do
    client = service()
    server = start_agent!(jido, Example)
    ctx = context([], %{service: {Service, client}})
    assert {:ok, _} = Server.call(server, Example.fetch_record_signal!("seed"), context: ctx)
    before = Server.snapshot(server)

    assert {:error, denied} =
             Server.call(server, Example.fetch_record_signal!("denied", false), context: ctx)

    assert Enum.any?(errors(denied), &(&1.message == "request denied"))
    assert length(Service.calls(client)) == 1

    assert {:error, stale} =
             Server.call(server, Example.fetch_record_signal!("stale", true, "r0"), context: ctx)

    assert Enum.any?(errors(stale), &(&1.message == "source revision is stale"))
    assert Service.calls(client) == [{:read, %{key: "seed"}}, {:read, %{key: "stale"}}]
    assert Server.snapshot(server) == before
    failed = start_supervised!({Service, %{read: {:error, :timeout}}}, id: :failed)

    assert {:error, unavailable} =
             Server.call(server, Example.fetch_record_signal!("failed"),
               context: %{service: {Service, failed}}
             )

    assert Enum.any?(
             errors(unavailable),
             &(&1.message == "read failed" and &1.details.reason == :timeout)
           )

    assert Service.calls(failed) == [{:read, %{key: "failed"}}]
    assert Server.snapshot(server) == before
  end

  test "context is isolated between Turns and repeated success advances only the commit revision",
       %{jido: jido} do
    first = service()

    second =
      start_supervised!({Service, %{read: {:ok, %{revision: "r1", answer: "second"}}}},
        id: :second
      )

    server = start_agent!(jido, Example)

    assert {:ok, committed} =
             Server.call(server, Example.fetch_record_signal!("one"),
               context: %{service: {Service, first}}
             )

    assert {:ok, ^committed} = Server.call(server, Example.fetch_record_signal!("one"))
    assert length(Service.calls(first)) == 1
    assert Server.snapshot(server) == %{agent: committed, state_version: 2}
    assert {:error, error} = Server.call(server, Example.fetch_record_signal!("two"))
    assert Enum.any?(errors(error), &(&1.message == "service context required"))
    assert Server.snapshot(server).state_version == 2

    assert {:ok, next} =
             Server.call(server, Example.fetch_record_signal!("two"),
               context: %{service: {Service, second}}
             )

    assert next.state.result.answer == "second"
    assert length(Service.calls(first)) == 1
    assert length(Service.calls(second)) == 1
    assert Server.snapshot(server).state_version == 3
  end
end
