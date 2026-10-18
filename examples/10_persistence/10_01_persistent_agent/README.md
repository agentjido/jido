# 10_01 Persistent Agent

An Agent creates revision zero, commits each successful Turn, and restores the exact saved state and revision.

## What you will learn

- How to configure persistence and restore an Agent.
- How durable identity and compare-and-swap protect the saved record.

## Read the code

Read [the persistent Agent](persistent_agent.ex), then the [identity probe](checkpoint_identity_probe.ex), and then the behavior tests.

## Run it

`mix test test/examples/10_persistence/10_01_persistent_agent --include example --seed 0`

Expected result: each successful Turn advances the saved revision. Restore returns the exact state. A checkpoint with another Agent ID is rejected.

## Important behavior

An identical-state success is still a commit and gets a new revision. Invalid input does not create a commit. A required missing record fails startup.

## Limits

The example uses local ETS storage. ETS data does not survive a BEAM restart.

## Files

- [Persistent Agent](persistent_agent.ex)
- [Identity probe](checkpoint_identity_probe.ex)
- [Agent tests](../../../test/examples/10_persistence/10_01_persistent_agent/persistent_agent_test.exs)
- [Identity test](../../../test/examples/10_persistence/10_01_persistent_agent/checkpoint_identity_test.exs)

```elixir
opts = [id: "counter", persistence: {Jido.Persistence.File, path: "tmp/counters"}]
{:ok, server} = Jido.start_agent(instance, Jido.Examples.Persistence.PersistentAgent,
  Keyword.put(opts, :persistence_mode, :create))
:ok = Jido.AgentServer.await_ready(server)
:ok = Jido.stop_agent(instance, server)
# Use the same ID and store:
{:ok, restored} = Jido.start_agent(instance, Jido.Examples.Persistence.PersistentAgent,
  Keyword.put(opts, :persistence_mode, :restore))
:ok = Jido.AgentServer.await_ready(restored)
```

`:create` requires a new record. `:restore` requires an existing record. The
[hibernate lesson](../10_02_hibernate_and_thaw/README.md) shows complete shutdown
and thaw rather than starting two owners for the same identity.

Next: [Hibernate And Thaw](../10_02_hibernate_and_thaw/README.md)
