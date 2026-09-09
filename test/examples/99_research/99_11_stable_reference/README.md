# FA-03: Stable Agent references and durable namespace identity

Status: **Core feature required; application reference works**.

Baseline on 2026-09-05: 2 passing and 1 failing checks.
As of 2026-09-07, the failing test is temporarily skipped, with reasons.
The original assertions remain. See the [research test policy](../README.md).

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

This is a secondary check. The missing-contract test remains skipped until
the feature is implemented. Do not reverse the original assertions.

[Source](../../../../examples/99_research/99_11_stable_reference/stable_reference.ex) · [Tests](stable_reference_test.exs)
