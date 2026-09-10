# Application examples

These examples combine the earlier Jido contracts into complete local
application patterns. Each example uses deterministic services and needs no
external account or credential.

## Learning order

1. [Audit](08_01_audit/README.md) — commit Agent and Plugin state only after a complete Flow succeeds.
2. [Subscription](08_02_subscription/README.md) — rebuild runtime resources from committed Plugin state.
3. [Inbox](08_03_inbox/README.md) — translate external input into Signals and reject duplicate events.
4. [Purpose Loop](08_06_purpose_loop/README.md) — continue bounded work through scheduled finite Turns.
5. [Fixed Group](08_07_fixed_group/README.md) — own stable roles and coordinate targeted work through a Bus.
6. [Elastic Group](08_08_elastic_group/README.md) — apply a bounded scale, recovery, and drain policy.

Identity and encrypted Signal handling now belong to the focused
[Plugin examples](../09_plugins/README.md).

## Run the section

```sh
mix test test/examples/08_applications --include example --seed 0
```

Expected result: each application commits its state, handles its documented
failure or recovery case, and cleans all owned processes.

## Shared support

- [Bus input Plugin](support/bus_input.ex) connects the fixed and elastic group roles to a local Bus.

## Limits

The fixed and elastic group examples show application policy built from public
Jido APIs. They do not define a Jido group or autoscaling API.
