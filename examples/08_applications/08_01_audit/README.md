# 08_01 Audit

An audit Plugin commits its state and runtime projection only after the complete
Agent Flow succeeds.

## What you will learn

- How a Flow returns Agent state and a typed Plugin Directive together.
- How a failed Flow leaves both committed states unchanged.

## Read the code

Read [the Agent and Flow](audit.ex), then [the audit Plugin](audit_plugin.ex).

## Run it

```sh
mix test test/examples/08_applications/08_01_audit --include example --seed 0
```

Expected result: one event commits, one invalid event fails, and the runtime
projection still matches the committed audit state.

## Important behavior

The named commit Action is a first-class Flow continuation. The Plugin updates
its runtime projection only after the Turn commits.

## Limits

The runtime projection is local and in memory. This example does not provide a
durable external audit store.

## Files

- [Agent and Flow](audit.ex)
- [Plugin](audit_plugin.ex)
- [Tests](../../../test/examples/08_applications/08_01_audit/audit_test.exs)

Previous: [Placement Policy](../../07_topology/07_08_placement_policy/README.md) | Next: [Subscription](../08_02_subscription/README.md)
