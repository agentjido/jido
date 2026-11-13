# 12_01 Persistent Agent

An Agent creates revision zero, saves each durable command, and restores the exact saved state and revision.

## What you will learn

- How to configure persistence and restore an Agent.
- How durable identity and compare-and-swap protect the saved record.

## Read the code

Read [the persistent Agent](persistent_agent.ex), then the [identity probe](checkpoint_identity_probe.ex), and then the behavior tests.

## Run it

`mix test.examples examples/12_persistence/12_01_persistent_agent --warnings-as-errors`

Expected result: each successful durable command saves its execution intent and
its terminal Agent state. It advances the saved revision twice. Restore returns
the exact state. A checkpoint with another Agent ID is rejected.

## Important behavior

An identical-state success still saves the execution intent and terminal Agent
state. Invalid Action input saves its intent and terminal failure without a
state change. A required missing record fails startup.

## Limits

The example uses local ETS storage. ETS data does not survive a BEAM restart.

## Files

- [Persistent Agent](persistent_agent.ex)
- [Identity probe](checkpoint_identity_probe.ex)
- [Agent tests](persistent_agent_test.exs)
- [Identity test](checkpoint_identity_test.exs)

```elixir
store = {Jido.Persistence.File, path: "tmp/counters"}
{:ok, _instance} = Jido.start_link(name: instance, namespace: "counters", persistence: store)
opts = [id: "counter"]
{:ok, server} = Jido.start_agent(instance, Jido.Examples.Persistence.PersistentAgent,
  Keyword.put(opts, :persistence_mode, :create))
:ok = Jido.AgentServer.await_ready(server)
:ok = Jido.stop_agent(instance, server)
# Use the same ID and instance Store:
{:ok, restored} = Jido.start_agent(instance, Jido.Examples.Persistence.PersistentAgent,
  Keyword.put(opts, :persistence_mode, :restore))
:ok = Jido.AgentServer.await_ready(restored)
```

`:create` requires a new record. `:restore` requires an existing record. The
[hibernate lesson](../12_02_hibernate_and_thaw/README.md) shows complete shutdown
and thaw rather than starting two owners for the same identity.

Previous: [Built-in Capabilities](../../11_built_in_capabilities/README.md) |
Next: [Hibernate And Thaw](../12_02_hibernate_and_thaw/README.md)
