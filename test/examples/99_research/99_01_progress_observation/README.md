# FA-07: Progress observation with recovery

Status: **Works as an application extension**.

Result on 2026-09-05: **5 passing checks; 0 failing acceptance checks.** All checks are enabled.

## Feature and proof

Waiting reasons are queryable. Ten live progress updates retain only three events, while committed state stays unchanged. Observer loss does not fail work. Cancellation stops active evaluation. A terminal result survives Agent persistence and observer replacement.

## Required change

No core feature is required for this proof. Keep application progress and bounded retention outside AgentServer.

## Scope

The buffer has one producer and demand-based reads. It sends no queue of notifications to slow consumers. Agent state stores terminal results; it does not persist transient progress. Persistence recovery uses an in-memory test adapter, not a fresh VM or database.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_01_progress_observation --include example --seed 0
```

This command passes with the current core. The extension policy is part of the example.

[Source](../../../../lib/examples/99_research/99_01_progress_observation/progress_observation.ex) · [Tests](progress_observation_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
