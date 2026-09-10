defmodule Jido.Examples.Factory.Workshop do
  @moduledoc "Checks a FIFO queue each second and runs one demonstration job at a time."
  use Jido.Agent, name: "factory_workshop"

  agent do
    schema Zoi.object(%{
             jobs: Zoi.map() |> Zoi.default(%{}),
             batches: Zoi.map() |> Zoi.default(%{}),
             queue: Zoi.list(Zoi.string()) |> Zoi.default([]),
             active_job_id: Zoi.string() |> Zoi.default(""),
             events: Zoi.list(Zoi.map()) |> Zoi.default([]),
             poll_count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             sequence: Zoi.integer() |> Zoi.default(0),
             step_delay_ms: Zoi.integer() |> Zoi.min(1) |> Zoi.default(2_000)
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/factory/workshop"

    route "examples.factory.workshop.boot" do
      action _input, schema: Zoi.object(%{}), context: context do
        if Map.has_key?(context.agent_state.scheduler.cron, "factory_poll") do
          {:ok, context.agent_state}
        else
          signal =
            Jido.Signal.new!("examples.factory.workshop.poll", %{},
              source: "/examples/factory/workshop/scheduler"
            )

          directive = Jido.Plugin.Scheduler.cron("factory_poll", "* * * * * * *", signal)
          {:ok, context.agent_state, [directive]}
        end
      end

      define :boot
    end

    route "examples.factory.command" do
      action input,
        schema: Jido.Examples.Factory.Protocol.command_schema(),
        context: context do
        Jido.Examples.Factory.Workshop.State.command(input, context.agent_state)
      end
    end

    route "examples.factory.workshop.submit_jobs" do
      action input,
        schema: Jido.Examples.Factory.Protocol.batch_schema(),
        context: context do
        Jido.Examples.Factory.Workshop.State.submit_batch(input, context.agent_state)
      end
    end

    route "examples.factory.inspect", Jido.Examples.Factory.Inspection

    route "examples.factory.workshop.poll" do
      action _input, schema: Zoi.object(%{}), context: context do
        Jido.Examples.Factory.Workshop.State.poll(
          context.agent_state,
          context.agent_id
        )
      end
    end

    route "examples.factory.work_item.progress" do
      action input,
        schema:
          Zoi.object(%{
            job_id: Zoi.string(),
            generation: Zoi.integer(),
            step: Zoi.integer()
          }),
        context: context do
        Jido.Examples.Factory.Workshop.State.progress(input, context.agent_state)
      end
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState

    route "jido.agent.child.exit" do
      action %{tag: tag}, context: context do
        Jido.Examples.Factory.Workshop.State.worker_exit(context.agent_state, tag)
      end
    end
  end

  @doc false
  def worker_tag(job), do: "work-#{job.id}-#{job.generation}"
end

defmodule Jido.Examples.Factory.Workshop.State do
  @moduledoc false

  alias Jido.Examples.Factory.{Protocol, WorkItem, Workshop}

  def command(%{operation: :status}, state), do: {:ok, state}

  def command(%{operation: :submit} = input, state) do
    case state.jobs[input.request_id] do
      %{goal: goal} when goal == input.goal -> {:ok, state}
      nil -> submit(input, state)
      _ -> Protocol.invalid("Request ID belongs to a different goal")
    end
  end

  def command(input, state) do
    case state.jobs[input.job_id] do
      nil -> Protocol.invalid("Job was not found")
      job -> control(input.operation, job, state)
    end
  end

  def submit_batch(%{request_id: id, goals: goals}, state) do
    case state.batches[id] do
      %{goals: ^goals} -> {:ok, state}
      nil -> enqueue(state, id, goals)
      _ -> Protocol.invalid("Batch ID belongs to a different job list")
    end
  end

  def poll(state, agent_id) do
    state = %{state | poll_count: state.poll_count + 1}
    start_next(state, agent_id)
  end

  def progress(input, state) do
    case state.jobs[input.job_id] do
      %{status: :running, generation: generation, step: step} = job
      when generation == input.generation and step == input.step and
             state.active_job_id == input.job_id ->
        advance(job, state)

      _ ->
        Protocol.invalid("Worker progress is stale")
    end
  end

  def worker_exit(%{active_job_id: ""} = state, _tag), do: {:ok, state}

  def worker_exit(state, tag) do
    job = state.jobs[state.active_job_id]

    if Workshop.worker_tag(job) == tag do
      job = %{job | status: :failed, result: "Worker stopped before completion"}
      next = %{state | active_job_id: "", jobs: Map.put(state.jobs, job.id, job)}
      {next, event} = Protocol.event(next, job, job.result)
      {:ok, next, [event]}
    else
      {:ok, state}
    end
  end

  defp submit(input, state) do
    cond do
      String.trim(input.goal) == "" ->
        Protocol.invalid("Supply a nonblank goal")

      map_size(state.jobs) >= 20 ->
        Protocol.invalid("The factory already holds 20 jobs")

      true ->
        job = %{
          id: input.request_id,
          goal: input.goal,
          status: :queued,
          step: 0,
          generation: 0,
          worker_id: "",
          result: ""
        }

        next = %{state | jobs: Map.put(state.jobs, job.id, job), queue: state.queue ++ [job.id]}
        {next, event} = Protocol.event(next, job, "Queued demonstration job")
        {:ok, next, [event]}
    end
  end

  defp enqueue(state, id, goals) do
    ids = goals |> Enum.with_index(1) |> Enum.map(fn {_, index} -> "#{id}/#{index}" end)

    cond do
      map_size(state.jobs) + length(goals) > 20 ->
        Protocol.invalid("Not enough capacity for this batch; the factory holds at most 20 jobs")

      Enum.any?(ids, &Map.has_key?(state.jobs, &1)) ->
        Protocol.invalid("A batch job ID is already in use")

      true ->
        {next, directives} =
          Enum.zip(ids, goals)
          |> Enum.reduce({state, []}, fn {job_id, goal}, {current, effects} ->
            {:ok, updated, job_effects} =
              command(%{operation: :submit, request_id: job_id, goal: goal}, current)

            {updated, effects ++ job_effects}
          end)

        batch = %{goals: goals, job_ids: ids}
        {:ok, %{next | batches: Map.put(next.batches, id, batch)}, directives}
    end
  end

  defp control(:pause, %{status: status} = job, state) when status in [:queued, :running],
    do: update(state, %{job | status: :paused, generation: job.generation + 1}, "Paused", [])

  defp control(:resume, %{status: :paused} = job, state) do
    next_job = %{job | status: :queued, generation: job.generation + 1}

    update(
      %{state | queue: state.queue ++ [job.id]},
      next_job,
      "Resumed at the end of the queue",
      []
    )
  end

  defp control(:cancel, %{status: status} = job, state)
       when status in [:queued, :running, :paused],
       do:
         update(
           state,
           %{job | status: :cancelled, generation: job.generation + 1},
           "Cancelled",
           []
         )

  defp control(_, _, _), do: Protocol.invalid("Operation is not valid for the current job state")

  defp update(state, job, detail, directives) do
    directives =
      if state.active_job_id == job.id,
        do: [
          Jido.Agent.Directive.stop_child(Workshop.worker_tag(state.jobs[job.id])) | directives
        ],
        else: directives

    next = %{
      state
      | jobs: Map.put(state.jobs, job.id, job),
        queue: if(job.status == :queued, do: state.queue, else: List.delete(state.queue, job.id)),
        active_job_id: if(state.active_job_id == job.id, do: "", else: state.active_job_id)
    }

    {next, event} = Protocol.event(next, job, detail)
    {:ok, next, [event | directives]}
  end

  defp start_next(%{active_job_id: "", queue: [id | rest]} = state, agent_id) do
    tag = Workshop.worker_tag(state.jobs[id])
    job = %{state.jobs[id] | status: :running, worker_id: "#{agent_id}/#{tag}"}
    next = %{state | active_job_id: id, queue: rest, jobs: Map.put(state.jobs, id, job)}
    {next, event} = Protocol.event(next, job, "Started demonstration job")

    directives = [
      event,
      Jido.Agent.Directive.spawn_child(WorkItem, tag,
        restart: :temporary,
        opts: %{
          initial_state: %{
            job_id: id,
            goal: job.goal,
            generation: job.generation,
            step: job.step,
            step_delay_ms: state.step_delay_ms
          }
        }
      ),
      Jido.Agent.Directive.emit_to_child(tag, WorkItem.start_signal!())
    ]

    {:ok, next, directives}
  end

  defp start_next(state, _agent_id), do: {:ok, state}

  defp advance(job, state) do
    step = job.step + 1
    done? = step == 3

    job = %{
      job
      | step: step,
        status: if(done?, do: :completed, else: :running),
        result: if(done?, do: "Demonstration complete: #{job.goal}", else: "")
    }

    next = %{
      state
      | jobs: Map.put(state.jobs, job.id, job),
        active_job_id: if(done?, do: "", else: job.id)
    }

    {next, event} = Protocol.event(next, job, "Demonstration step #{step}/3")

    directives =
      if done?, do: [Jido.Agent.Directive.stop_child(Workshop.worker_tag(job))], else: []

    {:ok, next, [event | directives]}
  end
end
