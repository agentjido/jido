# Scheduling

**After:** You can schedule delayed and recurring work reliably.

Jido provides three scheduling mechanisms: declarative schedules in the agent definition, one-time delays via `Schedule`, and dynamic recurring jobs via `Cron`. All are timer-based and tied to the agent's process lifecycle.

## Declarative Schedules

The simplest way to add recurring jobs is to declare them in your agent definition. Schedules target signal types, which get routed through `signal_routes/1` like any other signal:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [
      tick_count: [type: :integer, default: 0],
      last_cleanup: [type: :any, default: nil]
    ],
    schedules: [
      {"*/5 * * * *", "heartbeat.tick", job_id: :heartbeat},
      {"@daily", "cleanup.run", job_id: :cleanup, timezone: "America/New_York"}
    ]

  @signal_routes [
    {"heartbeat.tick", HeartbeatAction},
    {"cleanup.run", CleanupAction}
  ]

  def signal_routes(_ctx), do: @signal_routes
end
```

Declarative schedules are registered automatically when the AgentServer starts. They flow through the normal signal routing pipeline — the same `signal_routes/1`, strategy, and `cmd/2` that handle all other signals.

### Schedule Format

```elixir
schedules: [
  # Minimal: cron expression + signal type
  {"* * * * *", "my.signal"},

  # With job ID (for cancellation/upsert)
  {"*/5 * * * *", "heartbeat.tick", job_id: :heartbeat},

  # With timezone
  {"@daily", "cleanup.run", job_id: :cleanup, timezone: "America/New_York"}
]
```

Job IDs are automatically namespaced as `{:agent_schedule, agent_name, job_id}` to avoid collisions with plugin schedules and dynamic cron jobs.

### When to Use Declarative vs Dynamic

| Use case | Approach |
|----------|----------|
| Known at compile time, always runs | `schedules:` in agent definition |
| Depends on runtime state or user input | `Directive.cron/3` in an action |
| One-time delayed message | `Directive.schedule/2` in an action |

## Delayed Messages with Schedule

The `Schedule` directive sends a message back to your agent after a delay:

```elixir
defmodule RetryAction do
  use Jido.Action,
    name: "retry",
    schema: [attempt: [type: :integer, default: 1]]

  alias Jido.Agent.Directive

  def run(%{attempt: attempt}, context) do
    if attempt < 3 do
      retry_signal = Jido.Signal.new!(
        "task.retry",
        %{attempt: attempt + 1},
        source: "/agent/#{context.agent.id}"
      )

      {:ok, %{scheduled_retry: true}, [Directive.schedule(5_000, retry_signal)]}
    else
      {:error, Jido.Error.execution_error("Max retries exceeded")}
    end
  end
end
```

The message arrives as a signal after the delay. `Process.send_after/3` powers the implementation — if the agent crashes before the timer fires, the scheduled message is lost.

### Schedule API

```elixir
alias Jido.Agent.Directive

Directive.schedule(delay_ms, message)

Directive.schedule(5_000, :timeout)
Directive.schedule(1_000, {:check, some_ref})
Directive.schedule(30_000, my_signal)
```

## Dynamic Recurring Jobs with Cron

For schedules that depend on runtime state or user input, use the `Cron` directive to register recurring jobs dynamically from within an action:

```elixir
defmodule SetupCronAction do
  use Jido.Action, name: "setup_cron", schema: []

  alias Jido.Agent.Directive

  def run(_params, context) do
    tick_signal = Jido.Signal.new!(
      "heartbeat.tick",
      %{},
      source: "/agent/#{context.agent.id}"
    )

    {:ok, %{}, [
      Directive.cron("*/5 * * * *", tick_signal, job_id: :heartbeat)
    ]}
  end
end
```

### Cron Expressions

Standard 5-field expressions are supported:

| Expression | Meaning |
|------------|---------|
| `* * * * *` | Every minute |
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour |
| `0 0 * * *` | Daily at midnight |
| `0 9 * * MON` | Every Monday at 9 AM |

Aliases are also available:

| Alias | Equivalent |
|-------|------------|
| `@yearly` / `@annually` | `0 0 1 1 *` |
| `@monthly` | `0 0 1 * *` |
| `@weekly` | `0 0 * * 0` |
| `@daily` / `@midnight` | `0 0 * * *` |
| `@hourly` | `0 * * * *` |

### Timezone Support

```elixir
Directive.cron("0 9 * * *", morning_signal, 
  job_id: :morning_task,
  timezone: "America/New_York"
)
```

Default timezone is `Etc/UTC`.

### Upsert Behavior

Registering a cron job with an existing `job_id` cancels the old job and replaces it:

```elixir
Directive.cron("*/5 * * * *", tick_signal, job_id: :heartbeat)

Directive.cron("*/10 * * * *", tick_signal, job_id: :heartbeat)
```

The second directive cancels the 5-minute job and starts a 10-minute one.

## Cancelling Scheduled Jobs

Use `CronCancel` to stop a recurring job by its `job_id`:

```elixir
defmodule StopHeartbeatAction do
  use Jido.Action, name: "stop_heartbeat", schema: []

  alias Jido.Agent.Directive

  def run(_params, _context) do
    {:ok, %{}, [Directive.cron_cancel(:heartbeat)]}
  end
end
```

Cancelling a non-existent job is a no-op — it doesn't raise an error.

## Semantics & Guarantees

### Timer-Based, Not Persistent

Both `Schedule` and `Cron` use in-memory timers (`Process.send_after/3` and [SchedEx](https://github.com/SchedEx/SchedEx)).

**What this means:**

| Scenario | Behavior |
|----------|----------|
| Agent crashes before timer fires | Scheduled message lost |
| Agent restarts | Cron jobs must be re-registered |
| Node restart | All schedules lost |
| Timer fires during agent busy | Message queued in mailbox |

### Missed-Run Behavior

**Cron jobs do not catch up on missed runs.** If your agent is down when a cron tick would fire, that tick is simply missed. When the agent restarts and re-registers the job, scheduling resumes from the next scheduled time.

Example: An agent with a `@daily` job at midnight crashes at 11:50 PM and restarts at 12:30 AM. The midnight run is missed entirely — no catch-up occurs.

### Cleanup on Termination

When an agent stops (normal or crash), all its cron jobs are automatically cancelled in the `terminate/2` callback. You don't need to manually clean up.

## Idempotency Patterns

Since Jido scheduling provides **at-most-once delivery** (messages can be lost on crash), you need patterns to handle potential gaps or duplicates.

### Dedupe Keys

Track processed work to avoid duplicates if you retry externally:

```elixir
defmodule ProcessTickAction do
  use Jido.Action, name: "process_tick", schema: []

  alias Jido.Agent.StateOp

  def run(%{tick_id: tick_id}, context) do
    processed = Map.get(context.state, :processed_ticks, MapSet.new())

    if MapSet.member?(processed, tick_id) do
      {:ok, %{skipped: true}}
    else
      new_processed = MapSet.put(processed, tick_id)
      {:ok, %{processed: true}, [StateOp.set_state(%{processed_ticks: new_processed})]}
    end
  end
end
```

### Last-Run Timestamps

Track when work last ran to detect gaps:

```elixir
defmodule DailyReportAction do
  use Jido.Action, name: "daily_report", schema: []

  alias Jido.Agent.StateOp

  def run(_params, context) do
    last_run = Map.get(context.state, :last_report_at)
    now = DateTime.utc_now()

    if last_run && DateTime.diff(now, last_run, :hour) < 20 do
      {:ok, %{skipped: true, reason: "Too soon since last run"}}
    else
      report = generate_report()
      {:ok, %{report: report}, [StateOp.set_state(%{last_report_at: now})]}
    end
  end

  defp generate_report, do: %{generated_at: DateTime.utc_now()}
end
```

### Exactly-Once Semantics

Jido does **not** provide exactly-once guarantees for scheduled work. If you need exactly-once:

1. Use external persistent schedulers (Oban, Quantum with database backing)
2. Implement your own persistence layer
3. Use idempotency keys with external storage

For many use cases, at-most-once with last-run tracking is sufficient.

## Complete Example: Daily Report Generation

Here's a complete agent that generates a daily report using declarative schedules:

```elixir
defmodule DailyReportAgent do
  use Jido.Agent,
    name: "daily_report_agent",
    schema: [
      last_report_at: [type: {:custom, DateTime, :from_iso8601, []}, default: nil],
      report_count: [type: :integer, default: 0]
    ],
    schedules: [
      {"0 6 * * *", "report.generate",
        job_id: :daily_report, timezone: "America/New_York"}
    ]

  @signal_routes [
    {"report.generate", GenerateReportAction},
    {"report.cancel", CancelReportAction}
  ]

  def signal_routes(_ctx), do: @signal_routes

  defmodule GenerateReportAction do
    use Jido.Action, name: "generate_report", schema: []

    alias Jido.Agent.{Directive, StateOp}

    def run(_params, context) do
      last_run = Map.get(context.state, :last_report_at)
      now = DateTime.utc_now()

      cond do
        last_run && DateTime.diff(now, last_run, :hour) < 20 ->
          {:ok, %{skipped: true}}

        true ->
          report = build_report(context.state)
          count = Map.get(context.state, :report_count, 0)

          notification = Jido.Signal.new!(
            "notification.send",
            %{type: :report, data: report},
            source: "/agent/#{context.agent.id}"
          )

          {:ok, %{report: report}, [
            StateOp.set_state(%{
              last_report_at: now,
              report_count: count + 1
            }),
            Directive.emit(notification)
          ]}
      end
    end

    defp build_report(state) do
      %{
        generated_at: DateTime.utc_now(),
        report_number: Map.get(state, :report_count, 0) + 1,
        summary: "Daily metrics summary"
      }
    end
  end

  defmodule CancelReportAction do
    use Jido.Action, name: "cancel_report", schema: []

    def run(_params, _context) do
      {:ok, %{}, [Directive.cron_cancel({:agent_schedule, "daily_report_agent", :daily_report})]}
    end
  end
end
```

Start the agent — the daily report schedule is registered automatically:

```elixir
{:ok, _} = Jido.start_link(name: MyApp.Jido)

{:ok, pid} = Jido.start_agent(MyApp.Jido, DailyReportAgent,
  id: "report-agent-1"
)

# No setup signal needed — the schedule is already running
```

---

**Related guides:** [Directives](directives.md) • [Runtime](runtime.md)
