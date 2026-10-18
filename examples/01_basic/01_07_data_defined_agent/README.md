# 01_07 Data-defined Agent

One data definition uses the same Agent and Plugin contracts as the DSL.

Read [the definition and Action](data_defined_agent.ex), then the tests.
`Agent.define!/1` validates data. `Agent.instantiate!/2` adds identity and state.
`Agent.Codec.encode/1` returns a document and a trusted reference Registry.
JSON import resolves only references from that Registry and creates no atoms.

```sh
mix test test/examples/01_basic/01_07_data_defined_agent --include example --seed 0
```

Expected result: JSON round trips preserve the definition; direct and live
commands produce the same state. Import with an empty Registry fails.
The Registry from `encode/1` is local. Applications must retain or supply a
trusted Registry for stored documents. A document does not start a process.

See [Named Members](../../07_topology/07_01_independent/README.md) for a JSON
round trip that starts a composed Agent. The core authoring tests cover the
full DSL, data, and JSON format matrix.

- [Source](data_defined_agent.ex)
- [Tests](../../../test/examples/01_basic/01_07_data_defined_agent/data_defined_agent_test.exs)
- [Authoring tests](../../../test/authoring/agents/json_test.exs)

Previous: [Route Selection](../01_06_route_selection/README.md) | Next: [Agent Extension](../01_09_agent_extension/README.md)
