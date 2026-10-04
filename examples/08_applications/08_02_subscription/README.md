# 08_02 Subscription

A stateful Plugin keeps desired subscriptions in committed state and rebuilds
replaceable input resources after a restart.

## What you will learn

- How typed Plugin Directives change committed Plugin state.
- How a Plugin runtime reconstructs resources from committed state and version.
- How replacement rejects a stale resource and cleans the old process.

## Read the code

Read [the Agent](subscription.ex), then [the Plugin and runtime](subscription_plugin.ex).

## Run it

```sh
mix test test/examples/08_applications/08_02_subscription --include example --seed 0
```

Expected result: a subscription commits, resource replacement rejects the old
handle, and a restarted Plugin runtime reconstructs the same subscription and
state version. Agent shutdown stops the replacement resource.

## Important behavior

The desired subscription is durable Plugin-owned Agent data. `Jido.Plugin.Init`
gives each runtime generation one matching committed state and state version.
The runtime handle is temporary. A stale handle cannot submit input after a
new generation replaces it. The Agent owns the runtime and all its resources.

## Limits

The external subscription service is a local deterministic process. Provider
replay, duplicate event IDs, retry policy, and network errors are not part of
this example.

## Files

- [Agent](subscription.ex)
- [Plugin and runtime](subscription_plugin.ex)
- [Tests](../../../test/examples/08_applications/08_02_subscription/subscription_test.exs)

Previous: [Audit](../08_01_audit/README.md) | Next: [Inbox](../08_03_inbox/README.md)
