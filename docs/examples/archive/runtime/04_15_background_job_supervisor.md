> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Background Job Supervisor

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_15_background_job_supervisor`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Supervised runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Start, observe, cancel, and recover long work without blocking an Actor Turn.
- **User story:** As a user, I start a long local job, continue other work, and receive one durable completion result later.
- **Trigger or input:** Start, status, cancel, completion, failure, and recovery Signals.
- **Agent state:** Job ID, request digest, status, progress summary, result reference, delivery state, and idempotency key.
- **Actions or Flow:** A start Action commits pending job state and returns a runtime command. Completion or failure enters later as a new Signal and starts a new Turn.
- **External interactions:** A supervised fake worker with deterministic barriers and bounded output.
- **Runtime Directives or capabilities:** Start-job, cancel-job, and completion-delivery commands are handled by one runtime capability that owns supervised tasks.
- **Expected result:** The start Turn returns quickly, the worker survives caller activity, cancellation is idempotent, and exactly one terminal Signal records the result.
- **Failure cases:** Child crash, cancellation race, duplicate completion, missing result file, output limit, Actor restart, capability restart, or terminal delivery failure.
- **Jido features under pressure:** OTP supervision, runtime ownership, Directive dispatch, asynchronous Signal delivery, idempotency, recovery, and bounded observations.
- **Source framework and links:** [Pi background-tasks package](https://pi.dev/packages/pi-background-tasks), [Pi extension lifecycle](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md), and [Pi subagents package](https://pi.dev/packages/pi-subagents)


## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/runtime/04_15_background_job_supervisor/background_job_supervisor.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_15_background_job_supervisor/background_job_supervisor_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The controlled GenServer proves later result Signals. Plugin-owned task supervision, durable delivery, and recovery are not implemented.

An example-scope gap is not evidence of a core Jido defect.
