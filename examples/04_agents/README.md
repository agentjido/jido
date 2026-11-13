# 04 Agents

These offline lessons add logical identity, validated state, Signal routes, and
pure Turns to Flow behavior.

1. [Agent Definition](04_01_agent_definition/README.md) defines one Agent,
   creates its stable identity, and runs the same behavior in pure and hosted
   modes.
2. [State Schemas](04_02_state_schemas/README.md) validates defaults, command
   input, and the complete candidate state.
3. [Route Selection](04_03_route_selection/README.md) compares exact,
   wildcard, and fallback routes.
4. Pure execution with `Agent.cmd/3` is present in the first three lessons. A
   focused parity lesson remains to be added.
5. [Replies and Directives](04_05_replies_and_directives/README.md) separates
   candidate state from work that runs after commit.
6. Agent callbacks remain to be added.
7. A safe `Jido.Agent.View` projection remains to be added.
8. [Data-defined Agent](04_08_data_defined_agent/README.md) loads one trusted
   portable definition through the Catalog and Agent codec.
9. Controlled definition upgrades remain to be added.

Run the current chapter with:

```sh
mix test.examples examples/04_agents --warnings-as-errors
```

Expected result: all Agent examples pass without network access, credentials,
or a live model.

## Limits

This chapter does not own process lifecycle, durable recovery, or external
effects. AgentServer and the durability chapters own those contracts.

See [all examples](../README.md).
