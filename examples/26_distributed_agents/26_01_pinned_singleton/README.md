# 26_01 One pinned Agent for two nodes

Give both nodes the same Address for an operations coordinator. Node A owns
that namespace. Node B also hosts a billing coordinator under its own
namespace.

## What you will learn

- Configure one owner for a namespace and route a Signal to it with OTP RPC.
- Use a stable Address for a singleton and keep the owner node in application
  configuration.
- Handle a missing reply when the owner may already have accepted the Turn.

## Read the code

Read [the application call](pinned_singleton.ex) and the
[Counter Agent](../support/counter.ex). Jido lowers its inline Action to a
one-step Flow. Add the namespace's Jido instance to the supervisor on its
owner. Each caller supplies that owner and instance name.

## Run it

`mix test.examples examples/26_distributed_agents/26_01_pinned_singleton --warnings-as-errors`

Two calls commit revisions 1 and 2 on the same activation. The operations
counter reaches 3. A best-effort cast to billing changes only the billing
counter. A remote status check confirms the billing commit.

## Important behavior

The owner resolves or activates the Agent by its Address and commits each
Turn through its local Jido instance. The owner uses its local persistence
store. If the link fails, the routing function returns an unknown outcome and
makes one attempt. After reconnect, the same activation accepts work again.

One test cuts the link after Jido starts a Turn. The caller sees an unknown
outcome. The owner completes the Turn and commits the update once. The test
gate only controls when the link drops. The example uses ordinary Signals and
the normal Jido commit path.

## Limits

The application arranges for exactly one host to run each namespace. Loss of
that host makes the namespace unavailable. Its ETS state lasts only within
that BEAM.

## Core Fit and Gaps

**Application code.** Configuration decides which node owns each namespace.
Node discovery and access to the BEAM network belong to the deployment.

**Candidate Jido core change.** An Address lookup that returns the owner
instance could remove the explicit RPC from application code. Keep the
transport error distinct from a Turn result so that a caller can decide
whether to reconcile the outcome.

## Files

- [Application call](pinned_singleton.ex)
- [Counter Agent](../support/counter.ex)
- [Tests](pinned_singleton_test.exs)
- [Test gate](../support/turn_start_gate.ex)

[Next lesson](../26_02_move_a_durable_agent/README.md)
