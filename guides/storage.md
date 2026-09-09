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

Storage keys start with `jido:agent:v1:`. New outer records use format 2. The
reader also accepts Jido V3 outer format-1 active records. Old V2 and Actor
records require an explicit offline application conversion. There is no
automatic conversion.
Standalone Thread values remain, but old Thread stores and append APIs do not.
Ordinary directives are not a durable outbox. See the
[delivery and job examples](https://github.com/agentjido/jido/tree/v3-spike/examples/04_runtime/README.md).
