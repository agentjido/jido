# Bounded workers after V2

The public V2 WorkerPool and InstanceManager APIs are removed. V3 retains
AgentServer owner attachment, detach, touch, and idle-timeout controls.
It does not supply the old pre-warmed worker pool or automatic checkout facade.

Use explicit owned workers with a bounded capacity and stable job IDs. The
application must define queue order, retries, cancellation, and result ordering.
Use static Topology for a declared local system. Do not equate a Registry entry
with a cluster ownership lease.

See [bounded worker examples](../lib/examples/05_multi_agent/README.md),
[Factory queues](../lib/examples/06_factory/README.md), and [runtime](runtime.md).
