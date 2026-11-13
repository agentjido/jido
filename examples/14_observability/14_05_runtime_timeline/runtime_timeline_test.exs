Code.require_file("runtime_timeline.ex", __DIR__)

defmodule Jido.Examples.Observability.RuntimeTimelineTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Observability.RuntimeTimeline
  alias Jido.Examples.Observability.RuntimeTimeline.Agent

  test "public status values form an idle, waiting, completed timeline" do
    suffix = System.unique_integer([:positive])
    instance = :"runtime_timeline_example_#{suffix}"
    namespace = "examples/observability/runtime-timeline/#{suffix}"
    persistence = {Jido.Persistence.ETS, table: :"runtime_timeline_store_#{suffix}"}

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: persistence},
      id: instance
    )

    id = "timeline-#{suffix}"
    {:ok, server} = Jido.start_agent(instance, Agent, id: id, persistence: :inherit)
    assert :ok = AgentServer.await_ready(server)

    initial = RuntimeTimeline.project(:initial, AgentServer.status(server))
    assert initial.work_state == :idle
    assert initial.agent_revision == 0
    assert initial.active_turn_id == nil

    request_id = "request-1"
    assert {:ok, request} = Agent.request_signal(%{request_id: request_id})

    assert {:ok, %AgentServer.TurnResult{status: :waiting, turn_id: turn_id}} =
             AgentServer.call(server, request)

    waiting = RuntimeTimeline.project(:waiting, AgentServer.status(server))
    assert waiting.work_state == :waiting
    assert waiting.active_turn_id == turn_id
    assert waiting.wait_count == 1
    assert waiting.agent_revision == 0

    assert {:ok, release} = Agent.release_signal(request_id)

    assert {:ok, %AgentServer.TurnResult{status: :committed, turn_id: ^turn_id}} =
             AgentServer.call(server, release)

    completed = RuntimeTimeline.project(:completed, AgentServer.status(server))
    assert completed.work_state == :idle
    assert completed.active_turn_id == nil
    assert completed.wait_count == 0
    assert completed.agent_revision == 1
    assert completed.last_outcome.committed?
    assert AgentServer.snapshot(server).agent.state.status == :completed
    assert :ok = Jido.stop_agent(instance, server)
  end
end
