defmodule Jido.Examples.PendingJobRecovery do
  @moduledoc """
  An Agent saves approval and requires an explicit retry after runtime loss.

  Request and approval are separate Turns. Saved job input survives Agent or
  Plugin loss. A retry starts a fresh attempt and cancels an old task if it
  still exists. A running record does not prove that a task is still alive.
  """

  use Jido.Agent, name: "example_pending_job_recovery"

  alias Jido.Examples.Runtime.{JobRunner, JobRuntime}
  alias Jido.Examples.Runtime.JobRuntime.{Cancel, Submit}

  agent do
    schema Zoi.object(%{
             job_id: Zoi.string() |> Zoi.default(""),
             value: Zoi.integer() |> Zoi.default(0),
             status:
               Zoi.enum([:idle, :awaiting_approval, :running, :completed, :failed, :cancelled])
               |> Zoi.default(:idle),
             approved?: Zoi.boolean() |> Zoi.default(false),
             attempt_id: Zoi.string() |> Zoi.default(""),
             attempts: Zoi.list(Zoi.string()) |> Zoi.default([]),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             result: Zoi.string() |> Zoi.default("")
           })

    plugin JobRuntime
  end

  routes do
    signal_source "/examples/runtime/pending_jobs"

    route "examples.runtime.pending_jobs.request" do
      action input,
        schema:
          Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()}),
        context: context do
        state = context.agent_state

        if state.status in [:idle, :completed, :cancelled] and input.job_id not in state.seen do
          {:ok,
           %{
             state
             | job_id: input.job_id,
               value: input.value,
               status: :awaiting_approval,
               approved?: false,
               attempt_id: "",
               result: "",
               seen: state.seen ++ [input.job_id]
           }}
        else
          {:error, Jido.Action.Error.validation_error("job is active or already used")}
        end
      end

      define :request_job, args: [:job_id, :value]
    end

    route "examples.runtime.pending_jobs.approve" do
      action input,
        schema:
          Zoi.object(%{
            job_id: Zoi.string() |> Zoi.min(1),
            attempt_id: Zoi.string() |> Zoi.min(1)
          }),
        context: context do
        state = context.agent_state

        if state.status == :awaiting_approval and state.job_id == input.job_id do
          with {:ok, _runner} <- JobRunner.fetch(context) do
            Jido.Examples.PendingJobRecovery.begin_attempt(state, input.attempt_id)
          end
        else
          {:error, Jido.Action.Error.validation_error("job is not awaiting approval")}
        end
      end

      define :approve_job, args: [:job_id, :attempt_id]
    end

    route "examples.runtime.pending_jobs.retry" do
      action input,
        schema:
          Zoi.object(%{
            job_id: Zoi.string() |> Zoi.min(1),
            attempt_id: Zoi.string() |> Zoi.min(1)
          }),
        context: context do
        state = context.agent_state

        if state.approved? and state.status in [:running, :failed] and
             state.job_id == input.job_id do
          with {:ok, _runner} <- JobRunner.fetch(context),
               {:ok, candidate, directives} <-
                 Jido.Examples.PendingJobRecovery.begin_attempt(state, input.attempt_id) do
            {:ok, candidate, [struct!(Cancel, job_id: state.attempt_id) | directives]}
          end
        else
          {:error, Jido.Action.Error.validation_error("job is not approved for retry")}
        end
      end

      define :retry_job, args: [:job_id, :attempt_id]
    end

    route "examples.runtime.pending_jobs.cancel" do
      action %{job_id: job_id},
        schema: Zoi.object(%{job_id: Zoi.string()}),
        context: context do
        state = context.agent_state

        if state.job_id == job_id and
             state.status in [:awaiting_approval, :running, :failed] do
          directives =
            if state.status == :running,
              do: [struct!(Cancel, job_id: state.attempt_id)],
              else: []

          {:ok, %{state | status: :cancelled}, directives}
        else
          {:error, Jido.Action.Error.validation_error("job cannot be cancelled")}
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

        if state.attempt_id == input.job_id and state.status == :running do
          {:ok, %{state | status: input.status, result: input.result}}
        else
          {:error, Jido.Action.Error.validation_error("attempt result is stale")}
        end
      end

      define :settle_attempt
    end
  end

  @doc false
  def begin_attempt(state, attempt_id) do
    if attempt_id in state.attempts do
      {:error, Jido.Action.Error.validation_error("attempt ID is already used")}
    else
      candidate = %{
        state
        | status: :running,
          approved?: true,
          attempt_id: attempt_id,
          attempts: state.attempts ++ [attempt_id],
          result: ""
      }

      directive = struct!(Submit, job_id: attempt_id, value: state.value)
      {:ok, candidate, [directive]}
    end
  end
end
