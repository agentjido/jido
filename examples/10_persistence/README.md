# Persistence examples

These examples move from one durable Agent record to recovery after uncertain writes and external effects.

## Learning order

1. [Persistent Agent](10_01_persistent_agent/README.md) — create revision zero, commit Turns, restore exact state, and validate identity.
2. [Hibernate And Thaw](10_02_hibernate_and_thaw/README.md) — stop after a save and start from a required record.
3. [Portable Checkpoint](10_03_portable_checkpoint/README.md) — reject process-local values at the storage boundary.
4. [Plugin State Conversion](10_04_plugin_state_conversion/README.md) — convert one Plugin-owned value.
5. [Durable Delete](10_05_durable_delete/README.md) — keep a tombstone fence against stale writers.
6. [Indeterminate Write](10_06_indeterminate_write/README.md) — stop an activation after an uncertain result.
7. [Recoverable Delivery](10_07_recoverable_delivery/README.md) — save and resume external delivery intent.
8. [Definition Revision](10_08_definition_revision/README.md) — reject restore across an undeclared definition change.

## Run the section

`mix test test/examples/10_persistence --include example --seed 0`

Expected result: all examples pass without network access or credentials.

## Contract summary

- Persistence stores versioned checkpoints, not an event journal.
- Revision zero exists before a persistent Agent reports ready.
- Each successful Turn writes one new revision.
- Compare-and-swap blocks stale writes. A tombstone keeps that fence after delete.
- An indeterminate write stops the old activation. Recovery reads storage before more work starts.
- Persistence does not provide exclusive cluster ownership.

## Limits

The examples use deterministic local stores and controlled faults. Use the persistence conformance suites for all local adapters and the service suites for shared external adapters.
