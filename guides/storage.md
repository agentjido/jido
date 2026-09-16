# Persistence and recovery

Configure `persistence: {Adapter, options}` on the Jido instance. Jido does not
start the adapter's process. Implement binary `get/2` and atomic exact-byte
`compare_and_swap/4` from `Jido.Persistence.Adapter`. A new persistent
activation writes revision zero before its start call succeeds. A live success
follows the confirmed write. A stale revision fails. An indeterminate write
result stops that writer; it cannot evaluate another Action. Reactivation loads
authoritative state.

Use `Jido.hibernate(instance, pid)` to save and stop an idle Server. A successful
return includes completed termination. Use `Jido.thaw(instance, module, id)` to
restore it. Normal module restore uses the current definition and validates
complete state, identity, definition revision, and portability. Normal durable
delete writes a compact tombstone. It does not remove the storage key.

Without a persistence adapter, the instance RuntimeStore retains checkpoints
for local abnormal restarts. This is RAM in the same instance, not durable
storage. A clean stop deletes that runtime checkpoint. Loss of the instance or
VM loses it. Owned-child recovery has additional parent and spawn rules.

ETS is for development and tests and loses data when its owner VM stops.
File writes use atomic rename and a lock within one BEAM. One BEAM must own a
File directory; aliases or separate VM writers are not supported. Redis uses
an application-supplied command function and supports a millisecond TTL. That
TTL also applies to tombstones and limits the delayed-writer fence. Its unit
tests use a controlled command function; they do not prove Redis failover.

Compatible unnamed and namespaced Ref storage keys both start with
`jido:agent:v1:`. Their encoded identities differ. Compatible keys use outer
format 2; Ref keys use outer format 3. The reader also accepts Jido V3 outer
format-1 active records. A namespaced operation reads a lone compatible key
but rejects a compatible and Ref-key collision. It does not rewrite across
keys. Old V2 and Actor records require an explicit offline application
conversion.

## Check identity and portable state on load

The storage key, outer record, and nested checkpoint must name the same Agent.
A valid outer record cannot hide a checkpoint for another ID. Load rejects that
identity mismatch before it returns an Agent. Treat it as a bad record or an
incomplete migration; do not rewrite the key from the nested value. The
[identity regression](../test/jido/persistence/checkpoint_identity_test.exs)
checks this rule.

A domain schema can accept a value that cannot move between BEAM processes or
nodes. Save and load both check the complete checkpoint for portable terms. A
nested PID, port, reference, function, improper list, or non-byte bitstring
fails even when the domain field uses `Zoi.any()`. Store a stable identifier
and rebuild a process resource after restore. The
[portability regression](../test/jido/persistence/checkpoint_portability_test.exs)
checks both directions.

## Keep the delete fence

Normal durable delete writes a tombstone. A load reports the Agent as deleted,
but the old record revision still fences a delayed writer: an old
compare-and-swap cannot recreate the active record. A provider may later purge
the tombstone under an application retention policy; that ends the fence. The
[delete regression](../test/jido/persistence/record_lifecycle_test.exs)
checks the stale-writer result.

Standalone Thread values remain, but old Thread stores and append APIs do not.
Ordinary directives are not a durable outbox. See the
[delivery and job examples](https://github.com/agentjido/jido/blob/release/v3/examples/04_runtime/README.md).
