Code.require_file("job_runtime.ex", __DIR__)
Code.require_file("managed_jobs.ex", __DIR__)
Code.require_file("../support/job_runner.exs", __DIR__)

defmodule Jido.Examples.Runtime.ManagedJobsTest do
  use Jido.Test.Agent.FeatureSDKCase
  @moduletag :integration

  @moduletag group: :runtime
  alias Jido.Examples.ManagedJobs
  alias Jido.Examples.ManagedJobs.JobRuntime, as: Jobs
  alias Jido.Examples.ManagedJobs.JobRuntime.Server, as: JobServer

  defp start_job(jido) do
    agent = start_agent!(jido, ManagedJobs)

    {:ok, route_signal_1} = ManagedJobs.start_job_signal(%{job_id: "job", value: 3})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent, route_signal_1, context: Jido.Test.Examples.JobRunner.context(self()))

      assert turn_result.status in [:committed, :waiting]
      pending = Jido.AgentServer.snapshot(agent).agent
    )

    assert pending.state.status == :running
    assert_receive {:job_work, worker, 3}, 1000
    {agent, worker}
  end

  test "pure evaluation emits portable intent; live dispatch runs after the pending commit", %{
    jido: jido
  } do
    agent = start_agent!(jido, ManagedJobs)
    before = Jido.AgentServer.snapshot(agent)

    {:ok, command_signal_1} = ManagedJobs.start_job_signal(%{job_id: "job", value: 3})

    assert {:ok, candidate, [intent]} =
             ManagedJobs.cmd(
               before.agent,
               command_signal_1,
               context: Jido.Test.Examples.JobRunner.context(self())
             )

    assert candidate.state.status == :running
    assert Map.from_struct(intent) == %{job_id: "job", value: 3}
    assert Jido.AgentServer.snapshot(agent) == before
    refute_received {:job_work, _, _}

    {:ok, route_signal_2} = ManagedJobs.start_job_signal(%{job_id: "job", value: 3})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent, route_signal_2, context: Jido.Test.Examples.JobRunner.context(self()))

      assert turn_result.status in [:committed, :waiting]
    )

    assert_receive {:job_work, worker, 3}, 1000
    assert state(agent).status == :running
    assert Jido.AgentServer.snapshot(agent).agent_revision == 1
    send(worker, {:finish, {:ok, "artifact:6"}})
    eventually(fn -> state(agent).status == :completed end)
    assert state(agent).result == "artifact:6"
    assert Jido.AgentServer.snapshot(agent).agent_revision == 2

    assert JobServer.jobs(
             Jido.Test.AgentServer.ExampleRuntime.plugin(Jido.Test.AgentServer.ExampleRuntime.activation(agent), Jobs)
           ) == []
  end

  test "cancellation stops work and rejects its later result", %{jido: jido} do
    {agent, worker} = start_job(jido)
    ref = Process.monitor(worker)

    {:ok, route_signal_3} = ManagedJobs.cancel_job_signal(%{job_id: "job"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent, route_signal_3, [])

      assert turn_result.status in [:committed, :waiting]
    )

    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    before = Jido.AgentServer.snapshot(agent)

    {:ok, route_signal_4} =
      ManagedJobs.settle_signal(%{
        job_id: "job",
        status: :completed,
        result: "late"
      })

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _}} =
             Jido.AgentServer.call(agent, route_signal_4, [])

    assert Jido.AgentServer.snapshot(agent) == before
    assert state(agent).status == :cancelled
  end

  test "capability loss kills its work but requires explicit pending-job recovery", %{jido: jido} do
    {agent, worker} = start_job(jido)
    ref = Process.monitor(worker)
    activation = Jido.Test.AgentServer.ExampleRuntime.activation(agent)
    old = Jido.Test.AgentServer.ExampleRuntime.plugin(Jido.Test.AgentServer.ExampleRuntime.activation(agent), Jobs)
    Process.exit(old, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000

    runtime =
      eventually(fn ->
        case Jido.Test.AgentServer.ExampleRuntime.plugin(activation, Jobs) do
          pid when is_pid(pid) and pid != old -> pid
          _ -> nil
        end
      end)

    agent = Jido.AgentServer.Supervisor.worker(activation)
    assert :ok = Jido.AgentServer.await_ready(agent)
    assert JobServer.jobs(runtime) == []
    assert state(agent).status == :running

    {:ok, route_signal_5} = ManagedJobs.cancel_job_signal(%{job_id: "job"})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent, route_signal_5, [])

      assert turn_result.status in [:committed, :waiting]
    )

    {:ok, route_signal_6} = ManagedJobs.start_job_signal(%{job_id: "retry-with-new-id", value: 5})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent, route_signal_6, [])

      assert turn_result.status in [:committed, :waiting]
    )

    eventually(fn -> state(agent).status == :completed end)
    assert state(agent).result == "10"
  end
end
