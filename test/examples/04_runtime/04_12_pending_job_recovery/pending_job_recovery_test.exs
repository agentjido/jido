defmodule JidoTest.Examples.Runtime.PendingJobRecoveryTest do
  use JidoTest.FeatureSDKCase

  @moduletag group: :runtime

  alias Jido.Examples.ManagedJobs.{Jobs, Runtime}
  alias Jido.Examples.PendingJobRecovery, as: Example
  alias Jido.Examples.PersistenceProbeStore

  setup do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    {:ok, store: store}
  end

  test "saved approval requires an explicit new attempt after runtime loss", c do
    id = unique_id("example-pending-job")
    server = start_example(c, id, false)

    assert {:ok, _} = Example.request_job(server, "job-1", 3)

    assert {:ok, approved} =
             Example.approve_job(server, "job-1", "attempt-1", context: %{work: barrier()})

    assert approved.state.status == :running
    assert_receive {:job_work, first_task, 3}, 1_000

    server_ref = Process.monitor(server)
    task_ref = Process.monitor(first_task)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
    assert_receive {:DOWN, ^task_ref, :process, ^first_task, _reason}, 1_000
    eventually(fn -> Jido.whereis_agent(c.jido, id) == nil end)

    restored = start_example(c, id, :required)
    assert Server.agent(restored).state.status == :running
    assert Server.agent(restored).state.approved?
    assert Runtime.jobs(Server.children(restored)[{:plugin, Jobs}].pid) == []

    assert {:ok, retrying} =
             Example.retry_job(restored, "job-1", "attempt-2", context: %{work: barrier()})

    assert retrying.state.attempts == ["attempt-1", "attempt-2"]
    assert_receive {:job_work, second_task, 3}, 1_000

    before_stale = Server.snapshot(restored)

    assert {:error, _} =
             Example.settle_attempt(restored,
               input: %{job_id: "attempt-1", status: :completed, result: "stale"}
             )

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
