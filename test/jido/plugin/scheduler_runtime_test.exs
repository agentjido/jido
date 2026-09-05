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
