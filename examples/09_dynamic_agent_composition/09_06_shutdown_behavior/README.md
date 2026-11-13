# 09_06 Shutdown behavior

Separate activation shutdown from Jido instance shutdown and durable logical
Agent identity.

## What you will learn

- Stopping one activation leaves other independent Agents running.
- Stopping the Jido instance stops every resident activation that it owns.
- Durable Agent records can activate again under a new local instance binding.

## Read the code

Read [the explicit shutdown client](shutdown_behavior.ex) first.

## Run it

`mix test.examples examples/09_dynamic_agent_composition/09_06_shutdown_behavior --warnings-as-errors`

Expected result: one activation stops and restarts independently. Instance
shutdown then stops both processes, and both logical Agents activate again
from the same public persistence adapter.

## Important behavior

The Jido instance is the process owner. Each stable Address identifies a logical
Agent whose stored state can outlive that process owner. Shutdown does not
delete the durable record.

## Limits

This lesson proves local process ownership only. It does not provide remote
failover, a distributed lease, or automatic transfer to another instance.

## Core Fit and Gaps

Activation stop, instance stop, namespace rebinding, and durable reactivation
compose through public APIs. There is no public dynamic parent relation whose
shutdown policy can be transferred between live Agent owners.

## Files

- [Source](shutdown_behavior.ex)
- [Tests](shutdown_behavior_test.exs)

Previous: [Logical ownership transfer](../09_05_logical_ownership_transfer/README.md) | Next: [Declared topologies](../../10_declared_agent_topologies/README.md)
