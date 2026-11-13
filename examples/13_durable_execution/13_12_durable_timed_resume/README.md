# 13_12 Durable Timed Resume

A host reads `next_wake_at`, schedules a callback, and resumes one saved Flow.

## What you will learn

- How durable status exposes an absolute UTC wake time.
- How the host calls `Jido.Durable.resume/3` at that boundary.

## Read the code

Read [the timed Flow](timed_resume.ex), then [the test](timed_resume_test.exs).

## Run it

`mix test.examples examples/13_durable_execution/13_12_durable_timed_resume --warnings-as-errors`

Expected result: the bounded local timer resumes the saved Flow after its due
time.

## Important behavior

The durable layer saves timer state. It does not own a timer process.

## Limits

Host clock accuracy, timer delivery, and duplicate callbacks remain
application concerns.

## Core Fit and Gaps

The status and resume operations expose enough data for a host-owned timer.
No private scheduler API is required.

## Files

- [Timed Flow](timed_resume.ex)
- [Tests](timed_resume_test.exs)

[Previous: Signal Resume](../13_11_durable_signal_resume/README.md) |
[Next: Pending Job Recovery](../13_13_pending_job_recovery/README.md)
