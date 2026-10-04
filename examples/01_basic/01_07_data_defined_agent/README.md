# 01_07 Data-defined Agent

One neutral Agent definition uses the same validation, execution, and Plugin
contracts as a module-defined Agent.

## What you will learn

- How to build and instantiate an Agent with `Jido.Agent.new/1`.
- How a trusted `Jido.Codec.Registry` protects stored authoring documents.
- How Agent and Plugin Codecs preserve static configuration only.

## Read the code

Read [the data-defined Agent](data_defined_agent.ex), then read its behavior
test.

## Run it

```sh
mix test test/examples/01_basic/01_07_data_defined_agent --include example --seed 0
```

Expected result: the trusted document round trip succeeds, direct and live
execution select the same route, and an unknown target identifier is rejected.

## Important behavior

`Jido.Agent.set/2` validates a small state update before execution. The Agent
document contains the static definition, route target, schema identifier, and
Plugin declaration. It does not contain live identity, state, PIDs, or runtime
resources. Registry entries are an application allowlist. Document strings do
not become modules or atoms.

## Limits

This example does not load authoring documents from an untrusted network. An
application must add its own size, authorization, and storage policy.

## Files

- [Source](data_defined_agent.ex)
- [Tests](../../../test/examples/01_basic/01_07_data_defined_agent/data_defined_agent_test.exs)

Previous: [Route Selection](../01_06_route_selection/README.md) | Next: [Custom Signal Selection](../01_08_custom_signal_selection/README.md)
