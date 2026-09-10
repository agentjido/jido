# 99_08 Indeterminate Write

Status: implemented persistence safety regression; awaiting promotion.

An uncertain persistence result stops work on stale live state and blocks the
unconfirmed post-commit effect.

## What this proves

- Stored candidate bytes do not imply a committed live Turn.
- Later work cannot continue from state whose write result is uncertain.

## Read the code

Read [the probe Agent](indeterminate_write_probe.ex), then
[the shared fault store](../persistence_probe_store.ex).

## Run it

```sh
mix test test/examples/99_research/99_08_indeterminate_write --include example --seed 0
```

Expected result: storage contains the candidate revision, no output Signal is
dispatched, and the live server cannot execute a later command.

## Gap and limits

The core safety contract is implemented. The probe does not prescribe automatic
reload, a shutdown reason, database durability, or cross-node recovery.

## Files

- [Probe Agent](indeterminate_write_probe.ex)
- [Demo](demo.exs)
- [Shared fault store](../persistence_probe_store.ex)
- [Tests](../../../test/examples/99_research/99_08_indeterminate_write/indeterminate_write_test.exs)

Previous: [Checkpoint Portability](../99_07_checkpoint_portability/README.md) | Next: [Route Selection](../99_09_route_selection/README.md)
