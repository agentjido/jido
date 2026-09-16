# 99_06 Checkpoint Identity

Status: implemented persistence regression; lesson in the
[Persistence guide](../../../guides/storage.md#check-identity-and-portable-state-on-load).

The loader rejects a valid record whose nested checkpoint identity does not
match the identity requested by the caller.

## What this proves

- The record key and outer envelope cannot hide a different Agent identity.
- Identity validation occurs before the loaded Agent is returned.

## Read the code

Read [the probe Agent](checkpoint_identity_probe.ex), then
[the shared fault store](../persistence_probe_store.ex).

## Run it

```sh
mix test test/examples/99_research/99_06_checkpoint_identity --include example --seed 0
```

Expected result: the mismatched checkpoint load returns an identity error.

## Gap and limits

The core contract is implemented. This probe uses an in-memory byte adapter
and no VM restart. The stable guide states the load rule.

## Files

- [Probe Agent](checkpoint_identity_probe.ex)
- [Demo](demo.exs)
- [Shared fault store](../persistence_probe_store.ex)
- [Tests](../../../test/examples/99_research/99_06_checkpoint_identity/checkpoint_identity_test.exs)

Previous: [Shared Budget](../99_05_capacity_deadlines_cleanup/README.md) | Next: [Checkpoint Portability](../99_07_checkpoint_portability/README.md)
