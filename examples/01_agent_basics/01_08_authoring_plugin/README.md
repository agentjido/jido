# 01_08 Authoring Plugin

One authoring-only Plugin adds a validated owner label to an Agent definition.

## What you will learn

- How a provider declares its own Spark DSL section.
- How `lower/2` converts that section into contribution data.
- How `normalize/1` validates both DSL and Map authoring data.
- How the provider ID and version identify the stored contribution.

## Read the code

Read [the Plugin and Agent](authoring_plugin.ex), then read
[the tests](authoring_plugin_test.exs).
`Labels` owns the `labels` section. The Agent registers it with
`plugins: [Labels]` and declares `owner("examples")` in that section.

## Run it

```sh
mix test.examples examples/01_agent_basics/01_08_authoring_plugin
```

Expected result: DSL and Map authoring produce the same contribution. Invalid
labels and a version mismatch are rejected. A pure command updates the counter
and preserves the contribution.

## Important behavior

The Agent stores the provider data separately from core metadata and state:

```elixir
%{
  id: "examples.labels",
  provider: Jido.Examples.AuthoringPlugin.Labels,
  vsn: 1,
  data: %{owner: "examples"}
}
```

Lowering and validation must be deterministic. They must not start a process,
execute an Action, or contact an external service. This Plugin has no runtime
manifest. Pure Agent construction and command execution do not start an
AgentServer.

## Limits

This example teaches authoring-only Plugin data. It does not add runtime Plugin
behavior, topology endpoints, or a persistence upgrade Action. The provider
version identifies its contract; it does not perform an automatic upgrade.

## Files

- [Source](authoring_plugin.ex)
- [Tests](authoring_plugin_test.exs)

An authoring-only Plugin needs no runtime adapter and can be part of an
AgentServer definition. Pure authoring does not start runtime work.

Previous: [Data-defined Agent](../01_07_data_defined_agent/README.md) |
Next: [Flow Authoring](../../02_flow_authoring/README.md)
