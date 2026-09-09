# FA-03: Stable Agent references and durable namespace identity

Status: **Implemented and executable**.

Result on 2026-09-10: 3 passing acceptance checks.
See the [research test policy](../README.md).

## Feature and proof

A `Jido.Agent.Ref` survives persistent process replacement. Equal IDs in
separate namespaces remain isolated. Rebinding the same namespace to a new
local Jido instance restores the same durable identity.

## Required change

The Ref is used in live addressing and namespaced persistence without a saved
PID.

## Scope

`Jido.Agent.Ref` owns the identity value. The Jido instance owns exact local
namespace binding and Ref resolution. Persistence owns the Ref-derived key.
Storage uses the controlled in-memory byte adapter.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_11_stable_reference --include example --seed 0
```

This is a secondary acceptance check for the public Ref-first contract.

[Source](../../../../examples/99_research/99_11_stable_reference/stable_reference.ex) · [Tests](stable_reference_test.exs)
