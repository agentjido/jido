# FA-03: Stable Agent references and durable namespace identity

Status: **Core feature required; application reference works**.

Result on 2026-09-05: **2 passing checks; 1 failing acceptance checks.** All checks are enabled.

## Feature and proof

An application reference survives persistent process replacement. Equal IDs in separate namespaces remain isolated. Rebinding the same namespace to a new local Jido instance makes thaw return not_found because storage identity contains the old instance name.

## Required change

Use one canonical namespace, partition, and ID value in live addressing and persistence. Add the proposed Ref facade without requiring a saved PID.

## Scope

StableReference is an example-owned struct. Local lookup uses the current public Jido.whereis_agent/3 and AgentServer API. The passing controls do not establish a core Ref API. Storage uses the controlled in-memory byte adapter.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_11_stable_reference --include example --seed 0
```

This command returns a failing status until the stated core contract exists. Do not skip the assertion or reverse it to accept the current limitation.

[Source](stable_reference.ex) · [Tests](../../../test/examples/99_research/99_11_stable_reference/stable_reference_test.exs) · [Complete result log](../../../docs/examples/feature-acceptance-results.md)
