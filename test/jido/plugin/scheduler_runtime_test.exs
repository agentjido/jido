defmodule JidoTest.Plugin.SchedulerRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.Runtime
  alias Jido.Signal

  test "reconciliation retains live jobs and replaces dead jobs before their DOWN is handled" do
    runtime = runtime()
    spec = spec()
    assert {:reply, :ok, runtime} = reconcile(runtime, %{live: spec, dead: spec}, 1)
    {^spec, dead, old_ref} = runtime.cron_jobs.dead
    live = runtime.cron_jobs.live
    barrier = Process.monitor(dead)
    Process.exit(dead, :kill)
    assert_receive {:DOWN, ^barrier, :process, ^dead, :killed}, 1_000

    assert {:reply, :ok, runtime} = reconcile(runtime, %{live: spec, dead: spec}, 2)

    try do
      assert runtime.cron_jobs.live == live
      assert {^spec, replacement, new_ref} = runtime.cron_jobs.dead
      assert replacement != dead
      assert new_ref != old_ref
      assert Process.alive?(replacement)
      refute_received {:DOWN, ^old_ref, :process, ^dead, _}

      assert {:noreply, ^runtime} =
               Runtime.handle_info({:DOWN, old_ref, :process, dead, :killed}, runtime)
    after
      Runtime.terminate(:normal, runtime)
    end
  end

  test "activation stops at the first error and retains completed jobs and desired state" do
    runtime = %{runtime() | partition: self()}
    plain = spec()
    tracked = Map.put(plain, :generation, 1)
    # Use the map's enumeration order to select the successful and failing jobs.
    desired = %{first: plain, second: plain, third: plain}
    [success, failure, later] = Enum.map(desired, &elem(&1, 0))
    desired = desired |> Map.put(failure, tracked) |> Map.put(later, tracked)

    assert {:reply, {:error, {:cron_activation_failed, ^failure, :non_durable_occurrence_scope}},
            runtime} =
             reconcile(runtime, desired, 1)

    try do
      assert Map.keys(runtime.cron_jobs) == [success]
      assert runtime.desired_cron == desired
      assert runtime.last_reconciled_version == nil
      assert is_reference(runtime.retry_timer)
      {^plain, job, _ref} = runtime.cron_jobs[success]
      assert Process.alive?(job)
    after
      Runtime.terminate(:normal, runtime)
    end
  end

  test "a dead matching job is removed when its replacement cannot start" do
    runtime = runtime()
    spec = Map.put(spec(), :generation, 1)
    assert {:reply, :ok, runtime} = reconcile(runtime, %{job: spec}, 1)
    {^spec, job, ref} = runtime.cron_jobs.job
    barrier = Process.monitor(job)
    Process.exit(job, :kill)
    assert_receive {:DOWN, ^barrier, :process, ^job, :killed}, 1_000

    assert {:reply, {:error, {:cron_activation_failed, :job, :non_durable_occurrence_scope}},
            runtime} =
             reconcile(%{runtime | partition: self()}, %{job: spec}, 2)

    try do
      assert runtime.cron_jobs == %{}
      assert runtime.desired_cron == %{job: spec}
      assert runtime.last_reconciled_version == 1
      refute_received {:DOWN, ^ref, :process, ^job, _}
    after
      Runtime.terminate(:normal, runtime)
    end
  end

  defp runtime do
    {:ok, runtime, {:continue, :reconcile_agent}} =
      Runtime.init(%Init{
        agent_server: self(),
        agent_id: "scheduler-contract",
        module: Scheduler,
        options: [retry_delay_ms: 60_000]
      })

    runtime
  end

  test "failed cron restarts retry until the occurrence scope is valid" do
    runtime = %{runtime() | options: [retry_delay_ms: 60_000, test: self()]}
    spec = Map.put(spec(), :generation, 1)
    assert {:reply, :ok, runtime} = reconcile(runtime, %{job: spec}, 1)
    {^spec, job, ref} = runtime.cron_jobs.job
    Process.exit(job, :kill)
    assert_receive {:DOWN, ^ref, :process, ^job, :killed}

    assert {:noreply, failed} =
             Runtime.handle_info({:DOWN, ref, :process, job, :killed}, %{
               runtime
               | partition: self()
             })

    assert failed.cron_jobs == %{}
    assert_receive {:scheduler_retry_scheduled, :job, :killed, :non_durable_occurrence_scope}
    assert {:noreply, ^failed} = Runtime.handle_info({:retry_reconcile, make_ref(), 1}, failed)

    Process.cancel_timer(failed.retry_timer)

    assert {:noreply, retrying} =
             Runtime.handle_info({:retry_reconcile, failed.retry_token, 1}, failed)

    assert_receive {:scheduler_retry_failed, 1,
                    {:cron_activation_failed, :job, :non_durable_occurrence_scope}}

    assert retrying.retry_token != failed.retry_token
    Process.cancel_timer(retrying.retry_timer)

    assert {:noreply, recovered} =
             Runtime.handle_info({:retry_reconcile, retrying.retry_token, 1}, %{
               retrying
               | partition: nil
             })

    try do
      assert_receive {:scheduler_retry_succeeded, 1}
      assert recovered.last_reconciled_version == 1
      assert recovered.retry_timer == nil
      assert {^spec, replacement, _} = recovered.cron_jobs.job
      assert Process.alive?(replacement)
    after
      Runtime.terminate(:normal, recovered)
    end
  end

  test "delivery timeout and worker death release the active task" do
    for failure <- [:timeout, :down] do
      task =
        Task.async(fn ->
          receive do
            :finish -> :ok
          end
        end)

      timer = Process.send_after(self(), :unused_deadline, 60_000)
      runtime = %{runtime() | delivery_task: task, delivery_timeout: timer}
      assert {:noreply, ^runtime} = Runtime.handle_info({:delivery_timeout, make_ref()}, runtime)

      event =
        if failure == :timeout do
          {:delivery_timeout, task.ref}
        else
          Process.exit(task.pid, :kill)
          assert_receive {:DOWN, ref, :process, pid, :killed}
          assert ref == task.ref
          assert pid == task.pid
          {:DOWN, ref, :process, pid, :killed}
        end

      assert {:noreply, released} = Runtime.handle_info(event, runtime)
      assert released.delivery_task == nil
      assert released.delivery_timeout == nil
      refute Process.alive?(task.pid)
      assert Process.read_timer(timer) == false
      Runtime.terminate(:normal, released)
    end
  end

  defp spec do
    Scheduler.build_cron_spec("0 0 1 1 *", Signal.new!("test.tick", %{}, source: "/test"))
  end

  defp reconcile(runtime, desired, version) do
    signal = spec().message

    context = %DirectiveContext{
      turn_id: "turn",
      agent_id: runtime.agent_id,
      source_signal: signal,
      effective_signal: signal,
      state_version: version,
      plugin_state: %{cron: desired}
    }

    Runtime.handle_call(
      {:directive, Scheduler.cancel(:unused), context},
      {self(), make_ref()},
      runtime
    )
  end
end
