defmodule JidoTest.Examples.Durable.ImmediateApproval do
  @moduledoc false
  use Jido.Flow,
    name: "test_immediate_approval",
    schema: Zoi.object(%{request_id: Zoi.string() |> Zoi.min(1)})

  alias Jido.Examples.Durable.DurableWait.Approval

  flow do
    step "request", action: Approval.step_action("request"), params: %{request: input()}

    selection "decision" do
      needs ["request"]

      await("approved",
        event: "examples.durable.wait.approve",
        match: %{request_id: result("request", :request_id)}
      )

      await("cancelled",
        event: "examples.durable.wait.cancel",
        match: %{request_id: result("request", :request_id)}
      )

      timer("expired", after_ms: 0)
    end

    step "finish",
      action: Approval.step_action("finish"),
      params: %{values: %{request: result("request"), decision: result("decision")}}

    output result("finish")
  end
end

defmodule JidoTest.Examples.Durable.DurableWaitTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.DurableWait, as: Example

  defp start(c) do
    id = unique_id("approval")
    persistence = {Jido.Persistence.File, path: c.tmp_dir}

    assert {:ok, server} =
             Jido.start_agent(c.jido, Example,
               id: id,
               persistence: persistence,
               turn_timeout: :infinity
             )

    assert :ok = Server.await_ready(server)
    {:ok, request} = Example.request_signal(%{request_id: "report-1"})
    pending = Server.submit(server, request)
    {id, server, persistence, pending}
  end

  defp waiting(server) do
    eventually(fn ->
      case Server.status(server) do
        %{active: %{stage: :waiting}, waits: [wait]} = status -> {status, wait}
        _ -> nil
      end
    end)
  end

  test "one approval Flow survives hibernation with the same wait and deadline", c do
    {id, server, persistence, pending} = start(c)
    {status, wait} = waiting(server)
    assert status.active.worker_pid == nil
    assert Server.agent(server).state == %{request_id: "", status: :idle}
    assert :ok = Server.hibernate(server)
    assert {:error, _} = Server.await(pending)

    assert {:ok, awake} =
             Jido.thaw(c.jido, Example, id,
               persistence: persistence,
               turn_timeout: :infinity
             )

    assert :ok = Server.await_ready(awake)
    {restored, restored_wait} = waiting(awake)
    assert restored.active.turn_id == status.active.turn_id
    assert restored_wait == wait

    {:ok, wrong} = Example.resolve_signal(%{request_id: "other", decision: :approve})

    assert {:error, %{details: %{reason: :unmatched_input}}} =
             Server.deliver_wait(awake, wait.id, wrong)

    {:ok, approval} = Example.resolve_signal(%{request_id: "report-1", decision: :approve})
    assert :ok = Server.deliver_wait(awake, wait.id, approval)
    assert :ok = Server.quiesce(awake)
    assert Server.agent(awake).state == %{request_id: "report-1", status: :approved}
    assert Server.status(awake).durable_turn == %{id: status.active.turn_id, status: :completed}
    assert {:error, :not_waiting} = Server.deliver_wait(awake, wait.id, approval)
    assert :ok = Jido.stop_agent(c.jido, awake)
    assert Jido.agent_count(c.jido) == 0
  end

  test "a domain cancellation completes the same Flow and survives restore", c do
    {id, server, persistence, pending} = start(c)
    {_status, wait} = waiting(server)
    {:ok, cancel} = Example.resolve_signal(%{request_id: "report-1", decision: :cancel})
    assert :ok = Server.deliver_wait(server, wait.id, cancel)
    assert {:ok, cancelled, []} = Server.await(pending)
    assert cancelled.state == %{request_id: "report-1", status: :cancelled}
    assert :ok = Server.hibernate(server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.agent(awake) == cancelled
    assert Server.status(awake).active == nil
    assert :ok = Jido.stop_agent(c.jido, awake)
  end

  test "timer expiry completes the approval Flow and survives thaw", c do
    raw = Map.from_struct(Example.definition())
    [route] = raw.routes
    route = put_in(route.handler.target, JidoTest.Examples.Durable.ImmediateApproval)
    definition = Jido.Agent.define!(%{raw | routes: [route]})
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("expired-approval")

    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(c.jido, definition,
        id: id,
        persistence: persistence,
        turn_timeout: :infinity
      )

    {:ok, request} = Example.request_signal(%{request_id: "report-expired"})
    assert {:ok, expired, []} = Server.call(server, request)
    assert expired.state == %{request_id: "report-expired", status: :expired}
    assert Server.status(server).durable_turn.status == :completed
    assert :ok = Server.hibernate(server)
    assert {:ok, awake} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert :ok = Server.await_ready(awake)
    assert Server.agent(awake) == expired
    assert Server.status(awake).waits == []
    assert :ok = Jido.stop_agent(c.jido, awake)
  end
end
