# FA-03: Stable Agent references and durable namespace identity

Status: **Core Ref available; durable namespace identity required**.

Result on 2026-09-09: 2 passing and 1 skipped acceptance check.
The original assertions remain. See the [research test policy](../README.md).

## Feature and proof

A `Jido.Agent.Ref` survives persistent process replacement. Equal IDs in
separate namespaces remain isolated. Rebinding the same namespace to a new
local Jido instance makes thaw return `not_found` because storage identity
contains the old instance name.

## Required change

Use the Ref in live addressing and persistence without requiring a saved PID.

## Scope

`Jido.Agent.Ref` owns the identity value. This example owns the namespace to
Jido instance binding. Local lookup uses the current public
`Jido.whereis_agent/3` and AgentServer API. Storage uses the controlled
in-memory byte adapter.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_11_stable_reference --include example --seed 0
```

This is a secondary check. The missing-contract test remains skipped until
the feature is implemented. Do not reverse the original assertions.

[Source](../../../../examples/99_research/99_11_stable_reference/stable_reference.ex) · [Tests](stable_reference_test.exs)
