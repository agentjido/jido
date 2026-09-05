# DIST-03: distributed Agent authority

Status: **paused at a core design boundary**.

The current probe restores one logical Agent identity on another node and
rejects an older persistence revision after the replacement commits. Both
nodes can still start the identity at the same time because the Registry is
node-local.

The open decision is whether Jido core accepts a fencing contract from an
external placement service or owns a cluster claim, renewal, expiry, release,
and partition policy. See the [evidence and proposed boundary](../../../../docs/examples/dist-03-results.md).

[Probe Agent](distributed_authority_probe.ex) ·
[Acceptance notes](../../../../test/examples/99_research/99_02_distributed_authority/README.md) ·
[Research queue](../README.md)
