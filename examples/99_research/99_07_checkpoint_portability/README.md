# 99_07 Checkpoint Portability

Status: implemented persistence regression; lesson in the
[Persistence guide](../../../guides/storage.md#check-identity-and-portable-state-on-load).

The loader rejects a process-local value inserted into a stored Agent checkpoint.

## What this proves

- A domain schema does not by itself guarantee checkpoint portability.
- Save and load validation reject runtime-only BEAM terms.

## Read the code

Read [the probe Agent](checkpoint_portability_probe.ex), then
[the shared fault store](../persistence_probe_store.ex).

## Run it

```sh
mix test test/examples/99_research/99_07_checkpoint_portability --include example --seed 0
```

Expected result: a stored nested PID is rejected during load.

## Gap and limits

The core contract is implemented. This probe uses one PID and no VM restart.
The stable guide states the portable-state rule.

## Files

- [Probe Agent](checkpoint_portability_probe.ex)
- [Demo](demo.exs)
- [Shared fault store](../persistence_probe_store.ex)
- [Tests](../../../test/examples/99_research/99_07_checkpoint_portability/checkpoint_portability_test.exs)

Previous: [Checkpoint Identity](../99_06_checkpoint_identity/README.md) | Next: [Indeterminate Write](../99_08_indeterminate_write/README.md)
