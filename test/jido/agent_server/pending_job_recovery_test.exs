defmodule Jido.AgentServer.PendingJobRecoveryTest do
  use JidoTest.Case, async: false
  @moduletag capability: "REC-02"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PendingJobRecovery, as: Agent
  alias Jido.Examples.Runtime.JobRuntime, as: Jobs

  setup %{jido_pid: jido_pid} do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "jido-job-recovery-#{suffix}")

    on_exit(fn ->
      refute Process.alive?(jido_pid)
      File.rm_rf!(path)
    end)

    {:ok, persistence: {Jido.Persistence.File, path: path}, agent_id: unique_id()}
  end

  test "approval and fresh attempt identity are required in pure evaluation" do
    agent = Agent.new!()

    {:ok, command_signal_1} = Agent.request_job_signal(%{job_id: "job-1", value: 4})

    assert {:ok, waiting, []} =
             Agent.cmd(
               agent,
               command_signal_1
             )

    {:ok, command_signal_2} = Agent.retry_job_signal(%{job_id: "job-1", attempt_id: "attempt-1"})

    assert {:error, _} =
             Agent.cmd(
               waiting,
               command_signal_2
             )

    {:ok, command_signal_3} =
      Agent.approve_job_signal(%{job_id: "job-1", attempt_id: "attempt-1"})

    assert {:ok, running, [_]} =
             Agent.cmd(
               waiting,
               command_signal_3
             )

    {:ok, command_signal_4} = Agent.retry_job_signal(%{job_id: "job-1", attempt_id: "attempt-1"})

    assert {:error, _} =
             Agent.cmd(
               running,
               command_signal_4
             )

    {:ok, command_signal_5} = Agent.retry_job_signal(%{job_id: "job-1", attempt_id: "attempt-2"})

    assert {:ok, retried, [_cancel, _submit]} =
             Agent.cmd(
               running,
               command_signal_5
             )

    assert retried.state.attempts == ["attempt-1", "attempt-2"]
    assert {:error, _} = Agent.cmd(retried, result("attempt-1"))
    assert {:ok, completed, []} = Agent.cmd(retried, result("attempt-2"))
    assert {:error, _} = Agent.cmd(completed, result("attempt-2"))
  end

  test "a saved approval request survives Agent loss", c do
    server = start_agent(c)

    {:ok, route_signal_1} = Agent.request_job_signal(%{job_id: "job-1", value: 4})

    assert {:ok, waiting} =
             Jido.AgentServer.call(server, route_signal_1, [])

    kill(server)
    restored = start_agent(c, :required)
    assert Server.agent(restored) == waiting

    {:ok, route_signal_2} = Agent.approve_job_signal(%{job_id: "job-1", attempt_id: "attempt-1"})

    assert {:ok, _} =
             Jido.AgentServer.call(restored, route_signal_2, [])

    eventually(fn -> Server.agent(restored).state.status == :completed end)
    assert Server.agent(restored).state.result == "8"
  end

  for loss <- [:agent, :plugin] do
    @loss loss
    test "#{loss} loss permits explicit retry and rejects the old result", c do
      server = start_agent(c)

      {:ok, route_signal_3} = Agent.request_job_signal(%{job_id: "job-1", value: 4})

      assert {:ok, _} =
               Jido.AgentServer.call(server, route_signal_3, [])

      task = hold_attempt(server, :approve_job, "attempt-1")

      target =
        if @loss == :agent do
          server
        else
          Server.children(server)[{:plugin, Jobs}].pid
        end

      task_ref = Process.monitor(task)
      kill(target)
      assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}, 1000

      server =
        if @loss == :agent do
          start_agent(c, :required)
        else
          server
        end

      if @loss == :plugin do
        eventually(
          fn ->
            replacement = Server.children(server)[{:plugin, Jobs}].pid
            is_pid(replacement) and replacement != target and Process.alive?(replacement)
          end,
          timeout: 5000
        )
      end

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

    {:ok, route_signal_4} = Agent.request_job_signal(%{job_id: "job-1", value: 4})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_4, [])

    task = hold_attempt(server, :approve_job, "attempt-1")
    task_ref = Process.monitor(task)

    {:ok, route_signal_5} = Agent.cancel_job_signal(%{job_id: "job-1"})

    assert {:ok, cancelled} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}, 1000
    kill(server)
    restored = start_agent(c, :required)
    assert Server.agent(restored) == cancelled

    {:ok, route_signal_6} = Agent.approve_job_signal(%{job_id: "job-1", attempt_id: "attempt-2"})

    assert {:error, _} =
             Jido.AgentServer.call(restored, route_signal_6, [])

    {:ok, route_signal_7} = Agent.retry_job_signal(%{job_id: "job-1", attempt_id: "attempt-2"})

    assert {:error, _} =
             Jido.AgentServer.call(restored, route_signal_7, [])

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
    input = %{job_id: "job-1", attempt_id: attempt}

    {:ok, signal} =
      case operation do
        :approve_job -> Agent.approve_job_signal(input)
        :retry_job -> Agent.retry_job_signal(input)
      end

    assert {:ok, _} =
             Server.call(server, signal, context: JidoTest.JobRunner.context(self(), attempt))

    assert_receive {:job_work, task, ^attempt}, 1000
    task
  end

  defp result(attempt) do
    {:ok, command_signal_6} =
      Agent.settle_attempt_signal(%{job_id: attempt, status: :completed, result: "8"})

    command_signal_6
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end
end
