# 10_01 Named Agents

Two named members keep separate state under one owning Agent.

## What you will learn

- How `topology` declares members on a normal Agent definition.
- How `initial_state` gives each member its own starting values.
- How the owning AgentServer supervisor controls runtime lifetime.

## Read the code

Read the owner definition first, then the local Cell Agent and tests.

## Run it

```sh
mix test.examples examples/10_declared_agent_topologies/10_01_named_agents --warnings-as-errors
```

Expected result: The root and two members start. A command changes only the selected member.
Stopping the owner stops its member runtimes.

## Important behavior

Call `Jido.AgentServer.await_ready/2` before using the root. The tests use
`Jido.list_agents/2` and public snapshots to find example members by their
domain labels. They do not inspect private supervisor records.

These members have separate domain state and share the owning supervisor
lifetime. They are not independently supervised application roots.

## Limits

This example does not promise to preserve live member state when the whole
owner runtime restarts. A parent snapshot stores topology intent, not a
coordinated snapshot of running member states.

## Files

- [Source](independent.ex)
- [Cell Agent](cell.ex)
- [Tests](independent_test.exs)
- [Public runtime support](../support/runtime.ex)

```elixir
topology do
  agent :left, Jido.Examples.Topology.Independent.Cell do
    initial_state %{label: "left"}
  end
  agent :right, Jido.Examples.Topology.Independent.Cell do
    initial_state %{label: "right"}
  end
end
```

The JSON test encodes this definition with a trusted Registry, decodes it,
and starts the same named Agents. Data authoring does not start processes.
Continue with [Direct Connections](../10_02_direct_connections/README.md).

Previous: [Topology overview](../README.md) | Next: [Direct Connections](../10_02_direct_connections/README.md)

The JSON test builds its stable Registry independently. Each member declares
the core Scheduler Plugin. A scheduled command proves that an imported member
starts its Plugin runtime. Stopping the owner stops these runtimes too.
For creation requested by a Turn, see
[dynamic children](../../09_dynamic_agent_composition/09_01_child_lifecycle/README.md).
