defmodule JidoTest.Examples.Runtime.ManagedJobsTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :runtime
  alias Jido.Examples.ManagedJobs
  alias Jido.Examples.Runtime.JobRuntime, as: Jobs
  alias Jido.Examples.Runtime.JobRuntime.Server, as: JobServer

  defp start_job(jido) do
    agent = start_agent!(jido, ManagedJobs, error_policy: :log_only)

    {:ok, route_signal_1} = ManagedJobs.start_job_signal(%{job_id: "job", value: 3})

    assert {:ok, pending} =
             Jido.AgentServer.call(agent, route_signal_1,
               context: JidoTest.JobRunner.context(self())
             )

    assert pending.state.status == :running
    assert_receive {:job_work, worker, 3}, 1000
    {agent, worker}
  end

  test "pure evaluation emits portable intent; live dispatch runs after the pending commit", %{
    jido: jido
  } do
    agent = start_agent!(jido, ManagedJobs)
    before = Server.snapshot(agent)

    {:ok, command_signal_1} = ManagedJobs.start_job_signal(%{job_id: "job", value: 3})

    assert {:ok, candidate, [intent]} =
             ManagedJobs.cmd(
               before.agent,
               command_signal_1,
               context: JidoTest.JobRunner.context(self())
             )

    assert candidate.state.status == :running
    assert Map.from_struct(intent) == %{job_id: "job", value: 3}
    assert Server.snapshot(agent) == before
    refute_received {:job_work, _, _}

    {:ok, route_signal_2} = ManagedJobs.start_job_signal(%{job_id: "job", value: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(agent, route_signal_2,
               context: JidoTest.JobRunner.context(self())
             )

    assert_receive {:job_work, worker, 3}, 1000
    assert state(agent).status == :running
    assert Server.snapshot(agent).state_version == 1
    send(worker, {:finish, {:ok, "artifact:6"}})
    eventually(fn -> state(agent).status == :completed end)
    assert state(agent).result == "artifact:6"
    assert Server.snapshot(agent).state_version == 2
    assert JobServer.jobs(Server.children(agent)[{:plugin, Jobs}].pid) == []
  end

  test "cancellation stops work and rejects its later result", %{jido: jido} do
    {agent, worker} = start_job(jido)
    ref = Process.monitor(worker)

    {:ok, route_signal_3} = ManagedJobs.cancel_job_signal(%{job_id: "job"})

    assert {:ok, _} =
             Jido.AgentServer.call(agent, route_signal_3, [])

    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    before = Server.snapshot(agent)

    {:ok, route_signal_4} =
      ManagedJobs.settle_signal(%{
        job_id: "job",
        status: :completed,
        result: "late"
      })

    assert {:error, _} =
             Jido.AgentServer.call(agent, route_signal_4, [])

    assert Server.snapshot(agent) == before
    assert state(agent).status == :cancelled
  end

  test "capability loss kills its work but requires explicit pending-job recovery", %{jido: jido} do
    {agent, worker} = start_job(jido)
    ref = Process.monitor(worker)
    old = Server.children(agent)[{:plugin, Jobs}].pid
    Process.exit(old, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000

    runtime =
      eventually(fn ->
        case Server.children(agent)[{:plugin, Jobs}] do
          %{pid: pid} when is_pid(pid) and pid != old -> pid
          _ -> nil
        end
      end)

    assert JobServer.jobs(runtime) == []
    assert state(agent).status == :running

    {:ok, route_signal_5} = ManagedJobs.cancel_job_signal(%{job_id: "job"})

    assert {:ok, _} =
             Jido.AgentServer.call(agent, route_signal_5, [])

    {:ok, route_signal_6} = ManagedJobs.start_job_signal(%{job_id: "retry-with-new-id", value: 5})

    assert {:ok, _} =
             Jido.AgentServer.call(agent, route_signal_6, [])

    eventually(fn -> state(agent).status == :completed end)
    assert state(agent).result == "10"
  end
end
