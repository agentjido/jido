# 07_01 Named Agents

Two named members keep separate state under one owning Agent.

## What you will learn

- How `topology` declares members on a normal Agent definition.
- How `initial_state` gives each member its own starting values.
- How the owning AgentServer supervisor controls runtime lifetime.

## Read the code

Read the owner definition first, then the shared Cell Agent and tests.

## Run it

```sh
mix test test/examples/07_topology/07_01_independent --include example --seed 0
```

Expected result: The root and two members start. A command changes only the selected member.
Stopping the owner stops its member runtimes.

## Important behavior

Call `Server.await_ready(server)` before using the member runtimes.
`Server.children(server)` returns runtime records; its tags are opaque. The
tests identify these example members through their domain labels.

These members have separate domain state and share the owning supervisor
lifetime. They are not independently supervised application roots.

## Limits

This example does not promise to preserve live member state when the whole
owner runtime restarts. A parent snapshot stores topology intent, not a
coordinated snapshot of running member states.

## Files

- [Source](independent.ex)
- [Cell Agent](../support/cell.ex)
- [Tests](../../../test/examples/07_topology/07_01_independent/independent_test.exs)
- [Test runtime assertions](../../../test/examples/support/agent_topology_assertions.ex)

```elixir
topology do
  agent :left, Jido.Examples.Topology.Cell do
    initial_state %{label: "left"}
  end
  agent :right, Jido.Examples.Topology.Cell do
    initial_state %{label: "right"}
  end
end
```

The JSON test encodes this definition with a trusted Registry, decodes it,
and starts the same named Agents. Data authoring does not start processes.
Continue with [Direct Connections](../07_11_direct_connections/README.md).

Previous: [Topology overview](../README.md) | Next: [Direct Connections](../07_11_direct_connections/README.md)
