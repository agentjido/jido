# Bounded workers after V2

The public V2 WorkerPool and InstanceManager APIs are removed. V3 retains
AgentServer owner attachment, detach, touch, and idle-timeout controls.
It does not supply the old pre-warmed worker pool or automatic checkout facade.

Use explicit owned workers with a bounded capacity and stable job IDs. The
application must define queue order, retries, cancellation, and result ordering.
Use Agent topology for a declared local system. Do not equate a Registry entry
with a cluster ownership lease.

See [child ownership examples](https://github.com/agentjido/jido/blob/release/v3/examples/05_multi_agent/README.md),
[topology examples](../examples/07_topology/README.md), and [runtime](runtime.md).
