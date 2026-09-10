# 08_02 Subscription

A stateful Plugin keeps desired subscriptions in committed state and rebuilds
its runtime projection after a restart.

## What you will learn

- How typed Plugin Directives change committed Plugin state.
- How a Plugin runtime reconstructs external resources from that state.

## Read the code

Read [the Agent](subscription.ex), then [the Plugin and runtime](subscription_plugin.ex).

## Run it

```sh
mix test test/examples/08_applications/08_02_subscription --include example --seed 0
```

Expected result: a subscription commits, the Plugin runtime stops, and its
replacement reconstructs the same subscription.

## Important behavior

The desired subscription is durable Agent data. The runtime projection is
temporary and can be replaced without changing the Agent Turn.

## Limits

The external subscription service is an in-memory projection. Provider errors
and retry policy are not part of this example.

## Files

- [Agent](subscription.ex)
- [Plugin and runtime](subscription_plugin.ex)
- [Tests](../../../test/examples/08_applications/08_02_subscription/subscription_test.exs)

Previous: [Audit](../08_01_audit/README.md) | Next: [Inbox](../08_03_inbox/README.md)
