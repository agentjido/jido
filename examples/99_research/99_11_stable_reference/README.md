# FA-03: Stable Agent references and durable namespace identity

Status: **Core Ref available; durable namespace identity required**.

Result on 2026-09-09: **2 passing checks; 1 skipped acceptance check.**

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

The durable namespace-rebinding assertion stays skipped until persistence and
Jido instance namespace binding support the Ref. Do not reverse the assertion
to accept the current limitation.

[Source](stable_reference.ex) · [Tests](../../../test/examples/99_research/99_11_stable_reference/stable_reference_test.exs)
