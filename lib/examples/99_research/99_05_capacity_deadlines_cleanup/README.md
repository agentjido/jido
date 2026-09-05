# FA-09: Shared work budgets

Status: **Works as a local runtime extension**.

Result on 2026-09-05: **3 passing checks; 0 failing acceptance checks.** All checks are enabled.

## Feature and proof

Concurrent teams share two active slots and two queue slots. A fifth submission is rejected. Expired queued work never starts. Worker loss releases capacity. Normal service shutdown stops all monitored job Agents, Actions, call Tasks, and the Task supervisor.

## Required change

No core feature is required for this proof. The application admission service owns the shared budget and uses public Jido lifecycle APIs.

## Scope

Defaults are eight active jobs and 32 queued jobs; tests use two of each to force contention. Limits apply to accepted jobs, not raw BEAM mailbox messages or every internal process. Hard loss of the budget service, durable budgets, and arbitrary deep trees remain outside this proof.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_05_capacity_deadlines_cleanup --include example --seed 0
```

This command passes with the current core. The extension policy is part of the example.

[Source](shared_budget.ex) · [Tests](../../../../test/examples/99_research/99_05_capacity_deadlines_cleanup/shared_budget_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
