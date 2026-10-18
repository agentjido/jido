# 04_19 Definition Changes and Diff

An Action installs an exact route ahead of a wildcard without changing the running definition during pure evaluation.

## What you will learn

- How `route_add`, `routes_reorder`, and `route_remove` change accepted data.
- How the final Diff separates route changes from process changes.
- How a rejected batch preserves the accepted Agent and revision.

## Read the code

Read [the Agent](definition_changes.ex), then [the behavior tests](../../../test/examples/04_runtime/04_19_definition_changes/definition_changes_test.exs).

## Run it

```sh
mix test test/examples/04_runtime/04_19_definition_changes --include example --seed 0
```

Expected result: pure evaluation leaves the live snapshot unchanged. Live installation selects the exact handler; removal selects the wildcard again. Duplicate installation fails. Adding and removing the same temporary route produces an empty Diff.

## Important behavior and limits

```elixir
{:ok, signal} = Jido.Examples.DefinitionChanges.install_signal()
{:ok, candidate, directives} = Jido.Agent.cmd(agent, signal)
diff = Jido.Agent.Diff.between(agent, candidate)
Jido.Agent.Diff.changed?(diff, :routes) # true
```

Pure evaluation starts no process. The Diff describes final accepted data; it
is not an OTP instruction list. AgentServer commits a live change before it
reconciles resources. Use `Server.await_ready/1` after a live definition change.
An invalid batch changes neither the accepted Agent nor its revision.
Detailed mutation edge cases remain in core tests. This lesson does not add a
second router or automatic migration policy.

Previous: [Heartbeat](../04_18_heartbeat/README.md) | Next: [Multi-agent examples](../../05_multi_agent/README.md)
