# Managed Jobs

Feature ID: `04_04_managed_jobs`. Status: implemented within the tested scope.

## Added feature

An Agent-owned Plugin starts a linked task after commit and sends a later terminal Signal. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.ManagedJobs

{:ok, server} = Jido.start_agent(jido, ManagedJobs)
ManagedJobs.start_job(server, "job-1", 3)
```

## Evidence

6 enabled tests:

- pure evaluation emits portable intent; live dispatch runs after the pending commit.
- cancellation stops work and rejects its later result.
- worker failure becomes a terminal Signal and permits a fresh job.
- capability loss kills its work but requires explicit pending-job recovery.
- Agent shutdown stops the capability and its active task.
- invalid adapters and duplicate job IDs start no extra work.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_04_managed_jobs --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_04_managed_jobs/managed_jobs.ex) ·
[Tests](../../../../test/examples/04_runtime/04_04_managed_jobs/managed_jobs_test.exs)

## Boundary and next question

A capability restart loses active tasks and leaves pending Agent state. The example cancels that request before a new ID is submitted. Automatic replay needs application policy.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
