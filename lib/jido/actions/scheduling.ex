defmodule Jido.Actions.Scheduling do
  @moduledoc """
  Base actions for scheduling delayed signals and timeouts.

  These actions wrap the `Schedule` directive for common timing patterns.

  ## Usage

      use Jido.Agent,
        name: "timed_worker",
        signal_routes: [
          {"work.start", MyStartAction},  # Might schedule a timeout
          {"work.timeout", Jido.Actions.Status.MarkFailed}
        ]
  """

  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule ScheduleSignal do
    @moduledoc """
    Schedule a signal to be delivered after a delay.

    The signal will be delivered to the agent's own mailbox after
    the specified delay.

    ## Schema

    - `delay_ms` - Delay in milliseconds (required)
    - `signal_type` - Signal type to schedule (required)
    - `payload` - Signal payload data (default: %{})
    - `source` - Signal source path (default: "/scheduler")

    ## Example

        # Schedule a completion check
        {Jido.Actions.Scheduling.ScheduleSignal, %{
          delay_ms: 5000,
          signal_type: "work.check",
          payload: %{attempt: 1}
        }}
    """
    use Jido.Action,
      name: "schedule_signal",
      description: "Schedule a signal to be delivered after a delay",
      schema:
        Zoi.object(%{
          delay_ms: Zoi.integer(description: "Delay in milliseconds") |> Zoi.non_negative(),
          signal_type: Zoi.string(description: "Signal type to schedule"),
          payload: Zoi.map(description: "Signal payload data") |> Zoi.default(%{}),
          source: Zoi.string(description: "Signal source path") |> Zoi.default("/scheduler")
        })

    def run(%{delay_ms: delay, signal_type: type, payload: payload, source: source}, _context) do
      signal = Signal.new!(type, payload, source: source)
      directive = Directive.schedule(delay, signal)
      {:ok, %{scheduled_for_ms: delay, signal_type: type}, [directive]}
    end
  end

  defmodule ScheduleTimeout do
    @moduledoc """
    Schedule a timeout signal for deadline handling.

    Convenience wrapper that schedules a standard timeout signal
    that can be handled to fail the agent or take corrective action.

    ## Schema

    - `timeout_ms` - Timeout duration in milliseconds (required)
    - `timeout_id` - Identifier for this timeout (default: :default)
    - `signal_type` - Signal type for timeout (default: "agent.timeout")

    ## Example

        # Set a 30 second deadline
        {Jido.Actions.Scheduling.ScheduleTimeout, %{
          timeout_ms: 30_000,
          timeout_id: :work_deadline
        }}
    """
    use Jido.Action,
      name: "schedule_timeout",
      description: "Schedule a timeout signal for deadline handling",
      schema:
        Zoi.object(%{
          timeout_ms: Zoi.integer(description: "Timeout in milliseconds") |> Zoi.non_negative(),
          timeout_id:
            Zoi.any(description: "Identifier for this timeout") |> Zoi.default(:default),
          signal_type:
            Zoi.string(description: "Timeout signal type") |> Zoi.default("agent.timeout")
        })

    def run(%{timeout_ms: timeout, timeout_id: id, signal_type: type}, _context) do
      signal = Signal.new!(type, %{timeout_id: id}, source: "/timeout")
      directive = Directive.schedule(timeout, signal)
      {:ok, %{timeout_set: id, expires_in_ms: timeout}, [directive]}
    end
  end

  defmodule ScheduleCron do
    @moduledoc """
    Schedule a recurring signal using cron expression.

    The signal will be delivered on the cron schedule until cancelled.

    ## Schema

    - `cron` - Cron expression (required, e.g., "*/5 * * * *" for every 5 mins)
    - `job_id` - Identifier for this job (for cancellation)
    - `signal_type` - Signal type to schedule (required)
    - `payload` - Signal payload data (default: %{})
    - `timezone` - Timezone for cron evaluation (optional)

    ## Example

        # Heartbeat every minute
        {Jido.Actions.Scheduling.ScheduleCron, %{
          cron: "* * * * *",
          job_id: :heartbeat,
          signal_type: "agent.heartbeat"
        }}

        # Daily cleanup at 9am Eastern
        {Jido.Actions.Scheduling.ScheduleCron, %{
          cron: "0 9 * * *",
          job_id: :daily_cleanup,
          signal_type: "maintenance.cleanup",
          timezone: "America/New_York"
        }}
    """
    use Jido.Action,
      name: "schedule_cron",
      description: "Schedule a recurring signal using cron expression",
      schema:
        Zoi.object(%{
          cron: Zoi.string(description: "Cron expression"),
          job_id: Zoi.any(description: "Job identifier for cancellation") |> Zoi.default(nil),
          signal_type: Zoi.string(description: "Signal type to schedule"),
          payload: Zoi.map(description: "Signal payload data") |> Zoi.default(%{}),
          timezone: Zoi.string(description: "Timezone for cron evaluation") |> Zoi.default(nil)
        })

    def run(
          %{cron: cron_expr, job_id: job_id, signal_type: type, payload: payload, timezone: tz},
          _context
        ) do
      signal = Signal.new!(type, payload, source: "/cron")
      opts = if job_id, do: [job_id: job_id], else: []
      opts = if tz, do: Keyword.put(opts, :timezone, tz), else: opts
      directive = Directive.cron(cron_expr, signal, opts)
      {:ok, %{cron_scheduled: cron_expr, job_id: job_id}, [directive]}
    end
  end

  defmodule CancelCron do
    @moduledoc """
    Cancel a scheduled cron job by its ID.

    ## Schema

    - `job_id` - Identifier of the job to cancel (required)

    ## Example

        {Jido.Actions.Scheduling.CancelCron, %{job_id: :heartbeat}}
    """
    use Jido.Action,
      name: "cancel_cron",
      description: "Cancel a scheduled cron job",
      schema: Zoi.object(%{job_id: Zoi.any(description: "Job identifier to cancel")})

    def run(%{job_id: job_id}, _context) do
      directive = Directive.cron_cancel(job_id)
      {:ok, %{cancelled_job: job_id}, [directive]}
    end
  end
end
