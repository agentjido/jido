defmodule Jido.Examples.ScheduledOccurrenceRecovery do
  @moduledoc """
  An Agent saves each due schedule occurrence before it starts the work.

  Start the Agent with persistence and restore enabled for crash recovery. The
  Scheduler keeps one pending occurrence per job and retries it until the
  result Turn acknowledges it. The recorded tick list is only a small example
  diagnostic, so long-running applications need a bounded storage policy.
  """

  use Jido.Agent, name: "example_durable_schedule"

  agent do
    schema Zoi.object(%{
             generation: Zoi.integer() |> Zoi.default(0),
             ticks: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/runtime/durable_schedule"

    route "examples.runtime.schedule.arm", __MODULE__.Arm do
      define :arm_schedule, args: [:job_id, :cron]
    end

    route "examples.runtime.schedule.cancel", __MODULE__.Cancel do
      define :cancel_schedule, args: [:job_id]
    end

    route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue
    route "examples.runtime.schedule.tick", __MODULE__.Capture
  end
end
