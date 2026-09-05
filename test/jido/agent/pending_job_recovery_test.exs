defmodule JidoTest.Agent.PendingJobRecoveryTest do
  use JidoTest.Case, async: false
  @moduletag capability: "REC-02"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PendingJobRecovery, as: Agent
  alias Jido.Examples.ManagedJobs.Jobs

  setup do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "jido-job-recovery-#{suffix}")
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, persistence: {Jido.Persistence.File, path: path}, agent_id: unique_id()}
  end

  test "approval and fresh attempt identity are required in pure evaluation" do
    agent = Agent.new!()
    assert {:ok, waiting, []} = Agent.cmd(agent, Agent.request_job_signal!("job-1", 4))
    assert {:error, _} = Agent.cmd(waiting, Agent.retry_job_signal!("job-1", "attempt-1"))

    assert {:ok, running, [_]} =
             Agent.cmd(waiting, Agent.approve_job_signal!("job-1", "attempt-1"))

    assert {:error, _} = Agent.cmd(running, Agent.retry_job_signal!("job-1", "attempt-1"))

    assert {:ok, retried, [_cancel, _submit]} =
             Agent.cmd(running, Agent.retry_job_signal!("job-1", "attempt-2"))

    assert retried.state.attempts == ["attempt-1", "attempt-2"]
    assert {:error, _} = Agent.cmd(retried, result("attempt-1"))
    assert {:ok, completed, []} = Agent.cmd(retried, result("attempt-2"))
    assert {:error, _} = Agent.cmd(completed, result("attempt-2"))
  end

  test "a saved approval request survives Agent loss", c do
    server = start_agent(c)
    assert {:ok, waiting} = Agent.request_job(server, "job-1", 4)
    kill(server)
    restored = start_agent(c, :required)
    assert Server.agent(restored) == waiting
    assert {:ok, _} = Agent.approve_job(restored, "job-1", "attempt-1")
    eventually(fn -> Server.agent(restored).state.status == :completed end)
    assert Server.agent(restored).state.result == "8"
  end

  for loss <- [:agent, :plugin] do
    @loss loss
    test "#{loss} loss permits explicit retry and rejects the old result", c do
      server = start_agent(c)
      assert {:ok, _} = Agent.request_job(server, "job-1", 4)
      task = hold_attempt(server, :approve_job, "attempt-1")
      target = if @loss == :agent, do: server, else: Server.children(server)[{:plugin, Jobs}].pid
      task_ref = Process.monitor(task)
      kill(target)
      assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}, 1_000
      server = if @loss == :agent, do: start_agent(c, :required), else: server
      assert Server.agent(server).state.status == :running
      assert Server.agent(server).state.approved?
      second_task = hold_attempt(server, :retry_job, "attempt-2")
      before_stale = Server.snapshot(server)
      assert {:error, _} = Server.call(server, result("attempt-1"))
      assert Server.snapshot(server) == before_stale
      send(second_task, :release)
      eventually(fn -> Server.agent(server).state.status == :completed end)
      assert Server.agent(server).state.result == "8"
      assert {:error, _} = Server.call(server, result("attempt-2"))
    end
  end

  test "cancellation survives restart and rejects approval, retry, and late results", c do
    server = start_agent(c)
    assert {:ok, _} = Agent.request_job(server, "job-1", 4)
    task = hold_attempt(server, :approve_job, "attempt-1")
    task_ref = Process.monitor(task)
    assert {:ok, cancelled} = Agent.cancel_job(server, "job-1")
    assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}, 1_000
    kill(server)
    restored = start_agent(c, :required)
    assert Server.agent(restored) == cancelled
    assert {:error, _} = Agent.approve_job(restored, "job-1", "attempt-2")
    assert {:error, _} = Agent.retry_job(restored, "job-1", "attempt-2")
    assert {:error, _} = Server.call(restored, result("attempt-1"))
    assert Server.agent(restored) == cancelled
  end

  defp start_agent(c, restore \\ false) do
    assert {:ok, server} =
             Jido.start_agent(c.jido, Agent,
               id: c.agent_id,
               persistence: c.persistence,
               restore: restore,
               restart: :temporary
             )

    server
  end

  defp hold_attempt(server, operation, attempt) do
    observer = self()

    work = fn value ->
      send(observer, {:job_work, self(), attempt})

      receive do
        :release -> {:ok, Integer.to_string(value * 2)}
      end
    end

    assert {:ok, _} =
             apply(Agent, operation, [server, "job-1", attempt, [context: %{work: work}]])

    assert_receive {:job_work, task, ^attempt}, 1_000
    task
  end

  defp result(attempt),
    do: Agent.settle_attempt_signal!(input: %{job_id: attempt, status: :completed, result: "8"})

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end
end
