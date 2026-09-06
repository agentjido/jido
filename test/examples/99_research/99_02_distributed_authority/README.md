# FA-10: Fenced distributed ownership

Status: **Works with an explicit external authority**.

Result on 2026-09-05: **4 passing checks; 0 failing acceptance checks.** All checks are enabled.

## Feature and proof

Two Erlang nodes run real inventory Agents. Replacement fences old admission before Action work. Storage and the sink reject stale tokens. Authority loss rejects work. A disconnected old owner remains fenced after reconnection.

## Required change

No core feature is required for this controlled proof under the current admit callback and persistence adapter. Preserve an authority check before Action work if the proposed Plugin API removes admit/3.

## Scope

The external authority is a controlled GenServer, not a consensus service or production lease provider. Claim, byte writes, and sink checks serialize there. Core-only exclusive activation remains unsupported; the existing skipped DIST-03 test is unchanged. The disconnect test blocks automatic reconnection with a temporary peer cookie change.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_02_distributed_authority --include example --seed 0
```

This command passes with the current core. The extension policy is part of the example.

[Source](../../../../examples/99_research/99_02_distributed_authority/fenced_inventory.ex) · [Tests](fenced_inventory_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
