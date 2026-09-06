defmodule Jido.Examples.PendingJobRecovery.Request do
  @moduledoc false
  use Jido.Action,
    name: "example_request_job",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()})

  def run(input, %{agent_state: state}) do
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
end

defmodule Jido.Examples.PendingJobRecovery.Approve do
  @moduledoc false
  use Jido.Action,
    name: "example_approve_job",
    schema:
      Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), attempt_id: Zoi.string() |> Zoi.min(1)})

  def run(input, %{agent_state: state}) do
    if state.status == :awaiting_approval and state.job_id == input.job_id do
      Jido.Examples.PendingJobRecovery.begin_attempt(state, input.attempt_id)
    else
      {:error, Jido.Action.Error.validation_error("job is not awaiting approval")}
    end
  end
end

defmodule Jido.Examples.PendingJobRecovery.Retry do
  @moduledoc false
  use Jido.Action,
    name: "example_retry_job",
    schema:
      Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), attempt_id: Zoi.string() |> Zoi.min(1)})

  def run(input, %{agent_state: state}) do
    if state.approved? and state.status in [:running, :failed] and state.job_id == input.job_id do
      cancel = %Jido.Examples.ManagedJobs.CancelJob{job_id: state.attempt_id}

      with {:ok, candidate, directives} <-
             Jido.Examples.PendingJobRecovery.begin_attempt(state, input.attempt_id) do
        {:ok, candidate, [cancel | directives]}
      end
    else
      {:error, Jido.Action.Error.validation_error("job is not approved for retry")}
    end
  end
end

defmodule Jido.Examples.PendingJobRecovery.Cancel do
  @moduledoc false
  use Jido.Action, name: "example_cancel_job", schema: Zoi.object(%{job_id: Zoi.string()})

  def run(%{job_id: id}, %{agent_state: %{job_id: id} = state})
      when state.status in [:awaiting_approval, :running, :failed] do
    directives =
      if state.status == :running,
        do: [%Jido.Examples.ManagedJobs.CancelJob{job_id: state.attempt_id}],
        else: []

    {:ok, %{state | status: :cancelled}, directives}
  end

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("job cannot be cancelled")}
end

defmodule Jido.Examples.PendingJobRecovery.Settle do
  @moduledoc false
  use Jido.Action,
    name: "example_settle_attempt",
    schema:
      Zoi.object(%{
        job_id: Zoi.string(),
        status: Zoi.enum([:completed, :failed]),
        result: Zoi.string()
      })

  def run(%{job_id: attempt} = input, %{
        agent_state: %{attempt_id: attempt, status: :running} = state
      }) do
    {:ok, %{state | status: input.status, result: input.result}}
  end

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("attempt result is stale")}
end

defmodule Jido.Examples.PendingJobRecovery do
  @moduledoc """
  REC-02: saved approval and explicit recovery of a lost job attempt.

  Request and approval are separate Turns. The saved job input survives Agent
  or Plugin loss. `retry_job` starts a fresh attempt from that input and cancels
  an old task if one still exists. Results must match the active attempt ID.
  `cancel_job` abandons the request and remains effective after restore.

  This example reuses the Managed Jobs Plugin. It does not automatically retry
  work when a process restarts. `:running` records the last accepted attempt;
  it does not prove a task is still alive. The caller chooses retry or cancel.
  Attempt IDs are explicit input. Runtime adapters stay in caller context and
  must be supplied again if a retry needs one.
  """
  use Jido.Agent, name: "example_pending_job_recovery"

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

    plugin Jido.Examples.ManagedJobs.Jobs
  end

  routes do
    signal_source "/examples/recovery/jobs"

    route "recovery.job.request", __MODULE__.Request do
      define :request_job, args: [:job_id, :value]
    end

    route "recovery.job.approve", __MODULE__.Approve do
      define :approve_job, args: [:job_id, :attempt_id]
    end

    route "recovery.job.retry", __MODULE__.Retry do
      define :retry_job, args: [:job_id, :attempt_id]
    end

    route "recovery.job.cancel", __MODULE__.Cancel do
      define :cancel_job, args: [:job_id]
    end

    route "examples.jobs.settle", __MODULE__.Settle do
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

      directive = %Jido.Examples.ManagedJobs.Submit{job_id: attempt_id, value: state.value}
      {:ok, candidate, [directive]}
    end
  end
end
