# 08_03 Inbox

An input Plugin translates external events into Agent Signals and the Agent
records each event ID once.

## What you will learn

- How a Plugin runtime sends input through the Agent's public mailbox.
- How Agent state provides deterministic duplicate protection across bursts.

## Read the code

Read [the Agent](inbox.ex), then [the input Plugin](inbox_plugin.ex).

## Run it

```sh
mix test test/examples/08_applications/08_03_inbox --include example --seed 0
```

Expected result: a burst is processed, repeated IDs commit once, and input
continues after the Plugin runtime restarts.

## Important behavior

The Plugin owns temporary input transport. The Agent owns the durable set of
accepted event IDs.

## Limits

This example does not define sustained-overload policy or durable transport
acknowledgement.

## Files

- [Agent](inbox.ex)
- [Plugin](inbox_plugin.ex)
- [Tests](../../../test/examples/08_applications/08_03_inbox/inbox_test.exs)

Previous: [Subscription](../08_02_subscription/README.md) | Next: [Purpose Loop](../08_06_purpose_loop/README.md)
