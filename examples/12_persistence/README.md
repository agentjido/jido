# 12 Persistence

These examples move from one durable Agent record to recovery after uncertain writes and external effects.

## Learning order

1. [Persistent Agent](12_01_persistent_agent/README.md) — create revision zero, commit Turns, restore exact state, and validate identity.
2. [Hibernate And Thaw](12_02_hibernate_and_thaw/README.md) — stop after a save and start from a required record.
3. [Portable Checkpoint](12_03_portable_checkpoint/README.md) — reject process-local values at the storage boundary.
4. [Plugin State Conversion](12_04_plugin_state_conversion/README.md) — convert one Plugin-owned value.
5. [Durable Delete](12_05_durable_delete/README.md) — keep a tombstone fence against stale writers.
6. [Indeterminate Write](12_06_indeterminate_write/README.md) — stop an activation after an uncertain result.
7. [Recoverable Delivery](12_07_recoverable_delivery/README.md) — save and resume external delivery intent.
8. [Definition Revision](12_08_definition_revision/README.md) — retain saved definitions and code provenance; upgrade explicitly.

## Run the section

`mix test.examples examples/12_persistence`

Expected result: all examples pass without network access or credentials.

## Contract summary

- Persistence stores versioned checkpoints, not an event journal.
- Revision zero exists before a persistent Agent reports ready.
- Each successful Action Turn writes one new revision.
- Persistence also enables Flow recovery. Flows save acceptance and terminal status
  in Agent record revisions; step progress uses separate execution records.
- Compare-and-swap blocks stale writes. A tombstone keeps that fence after delete.
- Adapter compare-and-swap uses exact stored bytes or an opaque store token.
- Attachments block idle hibernation; detach and touch control the idle timer.
- An indeterminate write stops the old activation. Recovery reads storage before more work starts.
- Persistence does not provide exclusive cluster ownership.

## Limits

The examples use deterministic local stores and controlled faults. Use the
persistence conformance suites for all local adapters and the optional service
suites for shared external adapters.

Continue with [Durable Agents](../13_durable_execution/README.md) for an abrupt whole-BEAM
restart proof and the proposed execution recovery learning path.
