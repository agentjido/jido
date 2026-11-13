Code.require_file("../support/worker.ex", __DIR__)
Code.require_file("correlated_requests.ex", __DIR__)

defmodule Jido.Examples.MultiAgent.CorrelatedRequestsTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.AgentServer.TurnResult
  alias Jido.Examples.{CorrelatedRequests, Worker}

  setup do
    id = System.unique_integer([:positive])
    instance = :"correlated_requests_#{id}"
    namespace = "examples/correlated-requests/#{id}"
    table = :"correlated_requests_store_#{id}"

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: {Jido.Persistence.ETS, table: table}},
      id: instance
    )

    coordinator = Address.new!(namespace: namespace, id: "coordinator")
    worker = Address.new!(namespace: namespace, id: "worker")
    {:ok, ^coordinator} = Jido.create_agent(instance, coordinator, CorrelatedRequests)
    {:ok, ^worker} = Jido.create_agent(instance, worker, Worker)

    %{instance: instance, coordinator: coordinator, worker: worker}
  end

  test "explicit coordination preserves request correlation", c do
    assert {:ok, %TurnResult{status: :committed}} =
             CorrelatedRequests.run(c.instance, c.coordinator, c.worker, "request-1", 7)

    assert {:ok, coordinator} = Jido.activate_agent(c.instance, c.coordinator)

    assert %{request_id: "request-1", status: :completed, result: 14} =
             Jido.AgentServer.snapshot(coordinator).agent.state
  end

  test "an unrelated result does not change the committed coordinator", c do
    {:ok, request} = CorrelatedRequests.request_signal(%{request_id: "request-1"})
    assert {:ok, %TurnResult{status: :committed}} = Jido.call(c.instance, c.coordinator, request)

    {:ok, stale} = CorrelatedRequests.complete_signal(%{request_id: "old", value: 10})
    assert {:ok, %TurnResult{status: :failed}} = Jido.call(c.instance, c.coordinator, stale)

    assert {:ok, coordinator} = Jido.activate_agent(c.instance, c.coordinator)

    assert %{status: :waiting, result: nil} =
             Jido.AgentServer.snapshot(coordinator).agent.state
  end
end
