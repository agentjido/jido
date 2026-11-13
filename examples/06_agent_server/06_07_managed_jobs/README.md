# 06_07 Managed Jobs

An Agent commits portable job intent before a supervised Plugin starts linked work.

## What you will learn

- How a Plugin runtime owns linked Tasks and returns terminal Signals.
- How a `{module, client}` port keeps runtime services out of Agent state.

## Read the code

Read [the managed-jobs Agent](managed_jobs.ex) first. Then read the local
[job runtime](job_runtime.ex) and the behavior test.

## Run it

```sh
mix test.examples examples/06_agent_server/06_07_managed_jobs
```

Expected result: job intent commits before work starts, completion arrives in a
later Turn, and cancellation stops an active Task.

## Important behavior

Pure Agent evaluation returns portable intent and starts no process. Live Plugin
dispatch starts the Task after commit. Plugin loss removes active work but keeps
the Agent's running state.

## Limits

Active Tasks are not durable. Use `13_13_pending_job_recovery` when the
application must choose an explicit retry after loss.

## Files

- [Agent](managed_jobs.ex)
- [Local job runtime](job_runtime.ex)
- [Tests](managed_jobs_test.exs)

Previous: [Turn Control](../06_06_turn_control/README.md) |
Next: [Runtime Inspection](../06_08_runtime_inspection/README.md)
