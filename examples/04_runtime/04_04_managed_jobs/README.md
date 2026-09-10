# 04_04 Managed Jobs

An Agent commits portable job intent before a supervised Plugin starts linked work.

## What you will learn

- How a Plugin runtime owns linked Tasks and returns terminal Signals.
- How a `{module, client}` port keeps runtime services out of Agent state.

## Read the code

Read [the managed-jobs Agent](managed_jobs.ex) first. Then read the shared
[job runtime](../support/job_runtime.ex) and the behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_04_managed_jobs --include example --seed 0
```

Expected result: job intent commits before work starts, completion arrives in a
later Turn, and cancellation stops an active Task.

## Important behavior

Pure Agent evaluation returns portable intent and starts no process. Live Plugin
dispatch starts the Task after commit. Plugin loss removes active work but keeps
the Agent's running state.

## Limits

Active Tasks are not durable. Use `04_10_pending_job_recovery` when the
application must choose an explicit retry after loss.

## Files

- [Agent](managed_jobs.ex)
- [Shared job runtime](../support/job_runtime.ex)
- [Tests](../../../test/examples/04_runtime/04_04_managed_jobs/managed_jobs_test.exs)

Previous: [Bus Delivery](../04_03_bus_delivery/README.md) | Next: [Runtime Inspection](../04_05_runtime_inspection/README.md)
