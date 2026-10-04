# 08_01 Audit

The built-in Audit Plugin commits selected domain records with Agent state.

## What you will learn

- How a Flow returns Agent state and `Jido.Plugin.Audit.Record` together.
- How `max_entries` keeps only the newest records.
- How a failed Flow leaves domain and Audit Plugin state unchanged.

## Read the code

Read [the Agent and Flow](audit.ex), then read the behavior test.

## Run it

```sh
mix test test/examples/08_applications/08_01_audit --include example --seed 0
```

Expected result: three selected events commit with domain state, the oldest
record is removed, and one failed Flow adds no record.

## Important behavior

The named commit Action is a first-class Flow continuation. It selects a domain
fact and returns a typed Audit Directive with the domain candidate. The Plugin
has no runtime projection. Its bounded records are part of portable Agent state.

Audit records describe successful domain decisions. Use the
[Failure Outcome lesson](../../04_runtime/04_17_failure_outcome/README.md) when
an application must handle failed Turns at the Agent Server policy boundary.

## Limits

Audit Plugin state is durable only when the Agent uses persistence. This
example does not provide an external compliance archive.

## Files

- [Agent and Flow](audit.ex)
- [Tests](../../../test/examples/08_applications/08_01_audit/audit_test.exs)

Previous: [Additive Update](../../07_topology/07_09_additive_update/README.md) | Next: [Subscription](../08_02_subscription/README.md)
