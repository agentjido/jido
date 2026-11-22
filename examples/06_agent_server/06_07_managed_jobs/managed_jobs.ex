defmodule Jido.Examples.ManagedJobs do
  @moduledoc """
  An Agent commits job intent before a Plugin starts linked runtime work.

  A later Signal commits the result. Cancellation stops the task, and Agent
  shutdown stops the Plugin and its tasks. Active work is not durable. Use the
  pending-job recovery example when an application must recover lost work.
  """

  alias Jido.Joi

  use Jido.Agent,
    name: "example_managed_jobs",
    plugins: [Jido.Examples.ManagedJobs.JobRuntime]

  alias Jido.Examples.ManagedJobs.JobRunner
  alias Jido.Examples.ManagedJobs.JobRuntime.{Cancel, Submit}

  state do
    schema Joi.object(%{
             job_id: Joi.string() |> Joi.default(""),
             seen: Joi.list(Joi.string()) |> Joi.default([]),
             status: Joi.enum([:idle, :running, :completed, :failed, :cancelled]) |> Joi.default(:idle),
             result: Joi.string() |> Joi.default("")
           })
  end

  routes do
    signal_source "/examples/runtime/managed_jobs"

    route "examples.runtime.jobs.start", as: :start_job do
      action input,
        schema: Joi.object(%{job_id: Joi.string() |> Joi.min(1), value: Joi.integer()}),
        context: context do
        state = context.agent_state

        if state.status == :running or input.job_id in state.seen do
          {:error, Jido.Error.validation_error("job is active or already used")}
        else
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
    end

    route "examples.runtime.jobs.cancel", as: :cancel_job do
      action %{job_id: job_id},
        schema: Joi.object(%{job_id: Joi.string()}),
        context: context do
        state = context.agent_state

        if state.job_id == job_id and state.status == :running do
          {:ok, %{state | status: :cancelled}, [struct!(Cancel, job_id: job_id)]}
        else
          {:error, Jido.Error.validation_error("job is not running")}
        end
      end
    end

    route "examples.runtime.jobs.settle", as: :settle do
      action input,
        schema:
          Joi.object(%{
            job_id: Joi.string(),
            status: Joi.enum([:completed, :failed]),
            result: Joi.string()
          }),
        context: context do
        state = context.agent_state

        if state.job_id == input.job_id and state.status == :running do
          {:ok, %{state | status: input.status, result: input.result}}
        else
          {:error, Jido.Error.validation_error("job result is stale")}
        end
      end
    end
  end
end
