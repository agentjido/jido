# 04_07 Framework-neutral Agent views

Project safe Agent and operation metadata for a UI without contacting a
process.

## What you will learn

- `Jido.Agent.View.project/3` uses stable Catalog references.
- An instance view can include logical identity without Agent state.
- Metadata, Plugin options, route defaults, and module names stay private.

## Read the code

Read [the public view example](public_agent_view.ex) first.

## Run it

`mix test.examples examples/04_agents/04_07_agent_views --warnings-as-errors`

Expected result: the JSON-safe view describes one operation and does not
contain private state or defaults.

## Important behavior

The view is framework-neutral. It does not contact an Agent process and it is
not a Phoenix View or a runtime-state API.

## Limits

The caller must supply trusted Catalog identifiers. The view does not perform
authorization.

## Files

- [Source](public_agent_view.ex)
- [Tests](public_agent_view_test.exs)

Previous: [Agent callbacks](../04_06_agent_callbacks/README.md) | Next: [Data-defined Agent](../04_08_data_defined_agent/README.md)
