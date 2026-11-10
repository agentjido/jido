# 12 Plugin Applications

These examples combine the earlier Jido contracts into complete local
application patterns. Each example uses deterministic services and needs no
external account or credential.

## Learning order

1. [Audit](12_01_audit/README.md) — commit Agent and Plugin state only after a complete Flow succeeds.
2. [Subscription](12_02_subscription/README.md) — rebuild runtime resources from committed Plugin state.
3. [Inbox](12_03_inbox/README.md) — translate external input into Signals and reject duplicate events.
4. [Approval Workflow](12_04_approval_workflow/README.md) — correlate search, selection, approval, and one idempotent provider request.
5. [Purpose Loop](12_05_purpose_loop/README.md) — continue bounded work through scheduled finite Turns.

Identity and encrypted Signal handling now belong to the focused
[Plugin examples](../11_plugins/README.md).

## Run the section

```sh
mix test test/examples/12_plugin_applications --include example --seed 0
```

Expected result: each application commits its state, handles its documented
failure or recovery case, and cleans all owned processes.

## Limits

Fixed roles and Bus communication are covered by the topology examples.
Elastic scaling policy moved to the application demonstrations in JidoLab.
These local examples do not define distributed ownership or autoscaling APIs.
