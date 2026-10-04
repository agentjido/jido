# 08_03 Inbox

A Sensor Manager owns one tagged external input process. The Agent records each
translated event ID once.

## What you will learn

- How `Jido.Plugin.SensorManager` starts and stops a tagged sensor.
- How a sensor sends input through the Agent's public mailbox.
- How Agent state provides deterministic duplicate protection across bursts.
- How sensor and Manager failure rebuild the desired sensor set.
- How revision checks prevent stale reconciliation from restoring old input.

## Read the code

Read [the Agent](inbox.ex), then [the input sensor](inbox_sensor.ex).

## Run it

```sh
mix test test/examples/08_applications/08_03_inbox --include example --seed 0
```

Expected result: repeated IDs commit once. Sensor and Manager replacement keep
input available. A stopped sensor stays stopped when stale work arrives.

## Important behavior

The Sensor Manager stores the desired tagged sensor set in portable Plugin
state. Its runtime reconciles that set after commit and after replacement. A
failed sensor restarts while its tag remains desired. Reconciliation at an old
or equal state revision cannot replace a newer sensor set.

The sensor owns temporary input transport. The Agent owns duplicate policy and
the accepted event IDs. Agent shutdown stops the Manager and all sensors.

## Limits

This example does not define sustained-overload policy or durable transport
acknowledgement.

## Files

- [Agent](inbox.ex)
- [Sensor](inbox_sensor.ex)
- [Tests](../../../test/examples/08_applications/08_03_inbox/inbox_test.exs)

Previous: [Subscription](../08_02_subscription/README.md) | Next: [Approval Workflow](../08_04_approval_workflow/README.md)
