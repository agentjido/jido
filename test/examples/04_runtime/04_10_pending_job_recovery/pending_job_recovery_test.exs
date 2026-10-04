defmodule JidoTest.Examples.Runtime.PendingJobRecoveryTest do
  use JidoTest.FeatureSDKCase

  @moduletag group: :runtime

  alias Jido.Examples.PendingJobRecovery, as: Example
  alias JidoTest.Persistence.ProbeStore
  alias Jido.Examples.Runtime.JobRuntime, as: Jobs
  alias Jido.Examples.Runtime.JobRuntime.Server, as: JobServer

  setup do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    {:ok, store: store}
  end

  test "saved approval requires an explicit new attempt after runtime loss", c do
    id = unique_id("example-pending-job")
    server = start_example(c, id, false)

    {:ok, route_signal_1} = Example.request_job_signal(%{job_id: "job-1", value: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_1, [])

    {:ok, route_signal_2} =
      Example.approve_job_signal(%{job_id: "job-1", attempt_id: "attempt-1"})

    assert {:ok, approved} =
             Jido.AgentServer.call(server, route_signal_2,
               context: JidoTest.JobRunner.context(self())
             )

    assert approved.state.status == :running
    assert_receive {:job_work, first_task, 3}, 1000

    server_ref = Process.monitor(server)
    task_ref = Process.monitor(first_task)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1000
    assert_receive {:DOWN, ^task_ref, :process, ^first_task, _reason}, 1000
    eventually(fn -> Jido.whereis_agent(c.jido, id) == nil end)

    restored = start_example(c, id, :required)
    assert Server.agent(restored).state.status == :running
    assert Server.agent(restored).state.approved?
    assert JobServer.jobs(Server.children(restored)[{:plugin, Jobs}].pid) == []

    {:ok, route_signal_3} = Example.retry_job_signal(%{job_id: "job-1", attempt_id: "attempt-2"})

    assert {:ok, retrying} =
             Jido.AgentServer.call(restored, route_signal_3,
               context: JidoTest.JobRunner.context(self())
             )

    assert retrying.state.attempts == ["attempt-1", "attempt-2"]
    assert_receive {:job_work, second_task, 3}, 1000

    before_stale = Server.snapshot(restored)

    {:ok, route_signal_4} =
      Example.settle_attempt_signal(%{
        job_id: "attempt-1",
        status: :completed,
        result: "stale"
      })

    assert {:error, _} =
             Jido.AgentServer.call(restored, route_signal_4, [])

    assert Server.snapshot(restored) == before_stale
    send(second_task, {:finish, {:ok, "artifact:6"}})
    eventually(fn -> Server.agent(restored).state.status == :completed end)
    assert Server.agent(restored).state.result == "artifact:6"
  end

  defp start_example(c, id, restore) do
    assert {:ok, server} =
             Jido.start_agent(c.jido, Example,
               id: id,
               persistence: c.store,
               restore: restore,
               restart: :temporary
             )

    server
  end
end
