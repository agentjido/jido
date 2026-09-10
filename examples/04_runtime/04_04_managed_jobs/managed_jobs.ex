defmodule Jido.Examples.ManagedJobs do
  @moduledoc """
  An Agent commits job intent before a Plugin starts linked runtime work.

  A later Signal commits the result. Cancellation stops the task, and Agent
  shutdown stops the Plugin and its tasks. Active work is not durable. Use the
  pending-job recovery example when an application must recover lost work.
  """

  use Jido.Agent, name: "example_managed_jobs"

  alias Jido.Examples.Runtime.{JobRunner, JobRuntime}
  alias Jido.Examples.Runtime.JobRuntime.{Cancel, Submit}

  agent do
    schema Zoi.object(%{
             job_id: Zoi.string() |> Zoi.default(""),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             status:
               Zoi.enum([:idle, :running, :completed, :failed, :cancelled]) |> Zoi.default(:idle),
             result: Zoi.string() |> Zoi.default("")
           })

    plugin JobRuntime
  end

  routes do
    signal_source "/examples/runtime/managed_jobs"

    route "examples.runtime.jobs.start" do
      action input,
        schema:
          Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        state = context.agent_state

        cond do
          state.status == :running or input.job_id in state.seen ->
            {:error, Jido.Action.Error.validation_error("job is active or already used")}

          true ->
            with {:ok, _runner} <- JobRunner.fetch(context) do
              candidate = %{
                state
                | job_id: input.job_id,
                  seen: state.seen ++ [input.job_id],
                  status: :running,
                  result: ""
              }

              {:ok, candidate, [struct!(Submit, input)]}
            end
        end
      end

      define :start_job, args: [:job_id, :value]
    end

    route "examples.runtime.jobs.cancel" do
      action %{job_id: job_id},
        schema: Zoi.object(%{job_id: Zoi.string()}),
        context: context do
        state = context.agent_state

        if state.job_id == job_id and state.status == :running do
          {:ok, %{state | status: :cancelled}, [struct!(Cancel, job_id: job_id)]}
        else
          {:error, Jido.Action.Error.validation_error("job is not running")}
        end
      end

      define :cancel_job, args: [:job_id]
    end

    route "examples.runtime.jobs.settle" do
      action input,
        schema:
          Zoi.object(%{
            job_id: Zoi.string(),
            status: Zoi.enum([:completed, :failed]),
            result: Zoi.string()
          }),
        context: context do
        state = context.agent_state

        if state.job_id == input.job_id and state.status == :running do
          {:ok, %{state | status: input.status, result: input.result}}
        else
          {:error, Jido.Action.Error.validation_error("job result is stale")}
        end
      end

      define :settle
    end
  end
end
