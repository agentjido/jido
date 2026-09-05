defmodule JidoTest.Examples.Factory.WorkshopTest do
  use JidoTest.Case, async: true
  @moduletag :example
  @moduletag :integration
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{Conversation, Tools, Workshop}
  alias JidoTest.FactoryHTTP, as: HTTP

  defp command(agent, operation, id, goal \\ "") do
    evaluate(agent, "factory.command", %{
      operation: operation,
      request_id: id,
      job_id: id,
      goal: goal
    })
  end

  defp evaluate(agent, type, data) do
    {:ok, next, directives} = Workshop.cmd(agent, signal(type, data))
    {next, directives}
  end

  defp poll(agent), do: evaluate(agent, "factory.workshop.poll", %{})

  defp tick(agent) do
    job = agent.state.jobs[agent.state.active_job_id]

    evaluate(
      agent,
      "factory.worker.progress",
      Map.take(job, [:generation, :step]) |> Map.put(:job_id, job.id)
    )
  end

  test "only scheduler polls start queued work, with one active item and FIFO order" do
    {agent, [_event]} = command(Workshop.new!(), :submit, "first", "First goal")
    {agent, [_event]} = command(agent, :submit, "second", "Second goal")
    assert agent.state.queue == ["first", "second"]
    assert agent.state.active_job_id == ""
    {same, []} = command(agent, :submit, "first", "First goal")
    assert same.state == agent.state

    {agent,
     [
       _event,
       %Jido.Agent.Directive.SpawnAgent{restart: :temporary},
       %Jido.Agent.Directive.EmitToChild{}
     ]} = poll(agent)

    assert agent.state.active_job_id == "first"
    assert agent.state.queue == ["second"]
    assert agent.state.jobs["second"].status == :queued

    {busy, []} = poll(agent)
    assert busy.state.jobs == agent.state.jobs
    assert busy.state.active_job_id == "first"
    {agent, _} = tick(busy)
    {agent, _} = tick(agent)
    {agent, [_event, %Jido.Agent.Directive.StopChild{}]} = tick(agent)
    assert agent.state.jobs["first"].status == :completed
    assert agent.state.jobs["second"].status == :queued
    assert agent.state.active_job_id == ""
    {agent, _} = poll(agent)
    assert agent.state.active_job_id == "second"
    assert Enum.count(agent.state.jobs, fn {_, job} -> job.status == :running end) == 1
  end

  test "pause frees the active slot; resume queues at the end and stale work cannot advance" do
    {agent, _} = command(Workshop.new!(), :submit, "first", "First")
    {agent, _} = command(agent, :submit, "second", "Second")
    {agent, _} = poll(agent)
    {agent, _} = tick(agent)
    stale = signal("factory.worker.progress", %{job_id: "first", generation: 0, step: 1})
    {agent, _} = command(agent, :pause, "first")
    assert agent.state.active_job_id == ""
    assert {:error, _} = Workshop.cmd(agent, stale)
    {agent, _} = command(agent, :resume, "first")
    assert agent.state.queue == ["second", "first"]
    assert agent.state.jobs["first"].step == 1
    {agent, _} = poll(agent)
    assert agent.state.active_job_id == "second"
    assert {:error, _} = Workshop.cmd(agent, stale)
    {agent, _} = command(agent, :cancel, "second")
    assert agent.state.active_job_id == ""
    {agent, _} = poll(agent)
    assert agent.state.active_job_id == "first"
    {agent, _} = tick(agent)
    {agent, _} = tick(agent)
    assert agent.state.jobs["first"].status == :completed
  end

  test "paused and cancelled queued items do not block pending work" do
    {agent, _} = command(Workshop.new!(), :submit, "paused", "Paused")
    {agent, _} = command(agent, :submit, "cancelled", "Cancelled")
    {agent, _} = command(agent, :submit, "ready", "Ready")
    {agent, _} = command(agent, :pause, "paused")
    {agent, _} = command(agent, :cancel, "cancelled")
    assert agent.state.queue == ["ready"]
    {agent, _} = poll(agent)
    assert agent.state.active_job_id == "ready"
    assert agent.state.jobs["paused"].status == :paused
    assert agent.state.jobs["cancelled"].status == :cancelled
  end

  test "the one-second schedule stays active when idle and completes jobs in order", %{jido: jido} do
    system = HTTP.system!(jido, :workshop, step_delay_ms: 450)
    spec = HTTP.state(system.factory).scheduler.cron["factory_poll"]
    assert spec.cron_expression == "* * * * * * *"
    assert spec.message.type == "factory.workshop.poll"
    assert_eventually(HTTP.state(system.factory).poll_count >= 2, timeout: 3_000)
    assert HTTP.state(system.factory).events == []

    for id <- ["first", "second"] do
      assert {:ok, %{status: :queued}} =
               Tools.command(jido, system.factory_id, :submit, id, "", id)
    end

    assert_eventually(HTTP.state(system.factory).active_job_id == "first", timeout: 2_000)
    worker_id = HTTP.state(system.factory).jobs["first"].worker_id
    worker = eventually(fn -> Jido.whereis_agent(jido, worker_id) end)
    worker_ref = Process.monitor(worker)
    # Hold the real worker while the independent scheduler polls. Otherwise
    # the first job can finish before this test observes the next poll.
    :ok = :sys.suspend(worker)

    try do
      assert HTTP.state(system.factory).jobs["first"].status == :running
      busy_checks = HTTP.state(system.factory).poll_count
      assert_eventually(HTTP.state(system.factory).poll_count > busy_checks, timeout: 2_000)
      state = HTTP.state(system.factory)
      assert state.active_job_id == "first"
      assert state.jobs["second"].status == :queued
    after
      :ok = :sys.resume(worker)
    end

    assert HTTP.state(worker).job_id == "first"

    assert_eventually(HTTP.state(system.factory).jobs["second"].status == :completed,
      timeout: 5_000
    )

    assert_receive {:DOWN, ^worker_ref, :process, _, _}, 2_000

    assert_eventually(List.last(HTTP.state(system.conversation).events).status == "completed")
    events = HTTP.state(system.factory).events
    first_done = Enum.find_index(events, &(&1.job_id == "first" and &1.status == "completed"))

    second_started =
      Enum.find_index(
        events,
        &(&1.job_id == "second" and &1.detail == "Started demonstration job")
      )

    assert first_done < second_started
    assert HTTP.state(system.factory).active_job_id == ""
    assert HTTP.state(system.factory).queue == []

    assert_eventually(
      Enum.all?(HTTP.state(system.factory).jobs, fn {_, job} ->
        Jido.whereis_agent(jido, job.worker_id) == nil
      end)
    )
  end

  test "pause and cancel stop a real worker; resume starts a new attempt", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    assert {:ok, _} = Tools.command(jido, system.factory_id, :submit, "job", "", "Goal")
    assert_eventually(HTTP.state(system.factory).active_job_id == "job", timeout: 2_000)
    old_job = HTTP.state(system.factory).jobs["job"]
    worker = eventually(fn -> Jido.whereis_agent(jido, old_job.worker_id) end)
    ref = Process.monitor(worker)
    assert {:ok, _} = Tools.command(jido, system.factory_id, :pause, "pause", "job", "")
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000
    assert {:ok, _} = Tools.command(jido, system.factory_id, :resume, "resume", "job", "")
    assert_eventually(HTTP.state(system.factory).active_job_id == "job", timeout: 2_000)
    new_job = HTTP.state(system.factory).jobs["job"]
    assert new_job.worker_id != old_job.worker_id
    next_worker = eventually(fn -> Jido.whereis_agent(jido, new_job.worker_id) end)
    next_ref = Process.monitor(next_worker)

    stale =
      signal("factory.worker.progress", %{
        job_id: "job",
        generation: old_job.generation,
        step: old_job.step
      })

    assert {:error, _} = Server.call(system.factory, stale)
    assert {:ok, _} = Tools.command(jido, system.factory_id, :cancel, "cancel", "job", "")
    assert_receive {:DOWN, ^next_ref, :process, _, _}, 2_000
    assert HTTP.state(system.factory).jobs["job"].status == :cancelled
    assert HTTP.state(system.factory).active_job_id == ""
  end

  test "a worker exit fails its item and releases capacity for the next one", %{jido: jido} do
    system = HTTP.system!(jido, :workshop, step_delay_ms: 5_000)
    for id <- ["first", "second"], do: Tools.command(jido, system.factory_id, :submit, id, "", id)
    assert_eventually(HTTP.state(system.factory).active_job_id == "first", timeout: 2_000)
    worker_id = HTTP.state(system.factory).jobs["first"].worker_id
    worker = eventually(fn -> Jido.whereis_agent(jido, worker_id) end)
    Process.exit(worker, :kill)
    assert_eventually(HTTP.state(system.factory).jobs["first"].status == :failed, timeout: 2_000)

    try do
      assert_eventually(HTTP.state(system.factory).active_job_id == "second", timeout: 2_000)
    rescue
      error in ExUnit.AssertionError ->
        scheduler = Server.children(system.factory)[{:plugin, Jido.Plugin.Scheduler}].pid
        runtime = :sys.get_state(scheduler)

        clocks =
          Enum.map(runtime.cron_jobs, fn {key, {_, pid, _}} -> {key, :sys.get_state(pid)} end)

        IO.inspect(
          {Server.snapshot(system.factory), Server.status(system.factory), runtime, clocks},
          label: "Factory worker-exit diagnostics",
          limit: :infinity
        )

        reraise error, __STACKTRACE__
    end

    refute Jido.whereis_agent(jido, worker_id)
  end

  test "introspection tools expose current state and reject an unknown job", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    assert {:ok, _} = Tools.command(jido, system.factory_id, :submit, "job", "", "Goal")
    assert {:ok, _} = Tools.command(jido, system.factory_id, :pause, "pause", "job", "")
    tools = Tools.definitions(jido, system.factory_id, "inspect", %{}) |> Map.new(&{&1.name, &1})
    before = HTTP.state(system.factory)

    assert {:ok, status} = ReqLLM.Tool.execute(tools["factory_status"], %{})
    assert status.max_concurrent_jobs == 1
    assert status.scheduler.enabled
    assert status.scheduler.interval_ms == 1_000
    assert status.counts.paused == 1

    assert {:ok, %{job: %{goal: "Goal", status: :paused}, queue_position: nil}} =
             ReqLLM.Tool.execute(tools["factory_job"], %{"job_id" => "job"})

    assert {:ok, %{events: events}} =
             ReqLLM.Tool.execute(tools["factory_events"], %{"job_id" => "job"})

    assert hd(events).status == "queued"
    assert List.last(events).status == "paused"
    assert {:error, _} = ReqLLM.Tool.execute(tools["factory_job"], %{"job_id" => "missing"})
    assert HTTP.state(system.factory).jobs == before.jobs
    assert HTTP.state(system.factory).events == before.events
  end

  test "the conversation model can inspect the factory through its Signal tools", %{jido: jido} do
    system = HTTP.system!(jido, :workshop)
    test_pid = self()

    context =
      HTTP.context(fn body ->
        if length(body["messages"]) == 1 do
          HTTP.tool("factory_status", %{})
        else
          send(test_pid, {:inspection_result, Jason.encode!(body)})

          HTTP.text(
            "The queue is empty. The scheduler checks each second and capacity is one job."
          )
        end
      end)

    assert {:ok, _} =
             Conversation.ask(system.conversation, "inspect", "Inspect the factory",
               context: context
             )

    assert_receive {:inspection_result, body}, 5_000
    assert body =~ "max_concurrent_jobs"
    assert body =~ "interval_ms"
    assert body =~ "1000"
    assert_eventually(HTTP.state(system.conversation).answer =~ "capacity is one job")
  end

  test "repeated boot keeps one schedule and stopping the owner stops the scheduler", %{
    jido: jido
  } do
    system = HTTP.system!(jido, :workshop)
    assert {:ok, agent} = Workshop.boot(system.factory)
    assert map_size(agent.state.scheduler.cron) == 1
    runtime = Server.children(system.factory)[{:plugin, Jido.Plugin.Scheduler}].pid
    ref = Process.monitor(runtime)
    assert {:ok, _} = Tools.command(jido, system.factory_id, :submit, "job", "", "Goal")
    assert_eventually(HTTP.state(system.factory).active_job_id == "job", timeout: 2_000)
    worker_id = HTTP.state(system.factory).jobs["job"].worker_id
    worker = eventually(fn -> Jido.whereis_agent(jido, worker_id) end)
    worker_ref = Process.monitor(worker)
    assert :ok = Jido.stop_agent(jido, system.owner)
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, _, _}, 2_000
  end
end
