# 09_03 Process replacement

A stable Agent Address resolves a replacement process after abnormal process loss.

## What you will learn

- How logical Agent identity survives process replacement.
- How a Jido instance restores one activation from its durable record.
- Why replacement is not adoption or ownership transfer.

## Read the code

Read [the stable replacement client](orphan_adoption.ex) and
[the tests](orphan_adoption_test.exs).

The Jido instance restarts the activation from its durable record. The logical
Agent Address and activation ID stay stable while the worker PID changes.

## Run it

```sh
mix test.examples examples/09_dynamic_agent_composition/09_03_orphan_adoption --warnings-as-errors
```

## Important behavior

This is process replacement, not adoption or ownership transfer. Jido core has
no current public API for dynamic child adoption or runtime ownership transfer.

## Limits

The replacement stays in one Jido instance. The example does not prove remote
failover, adoption, or transfer of process ownership.

## Files

- [Source](orphan_adoption.ex)
- [Tests](orphan_adoption_test.exs)

Previous: [Correlated Requests](../09_02_correlated_requests/README.md) | Next: [Independent Agents](../09_04_independent_agents/README.md)
