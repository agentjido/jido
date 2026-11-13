# 15_13 Skills and Tool Sources

Trusted execution context combines one local skill with one deterministic
MCP-shaped ToolSource.

## What you will learn

- How `Jido.AI.Skill` publishes a lazy `load_skill` tool.
- How `Jido.AI.ToolSource` loads and runs portable dynamic tools.
- Why request data cannot add trusted tool sources.
- Where official MCP client ownership belongs.

## Read the code

Read [the offline ToolSource](tool_sources.ex), then the
[skill fixture](fixtures/skills/focused-review/SKILL.md), and then the test.

## Run it

`mix test.examples examples/15_ai_agents/15_13_skills_and_tool_sources --warnings-as-errors`

Expected result: trusted context loads `load_skill` and `remote_lookup`, both
tools return deterministic values, and request data loads no source.

## Important behavior

An Agent definition owns its protected static Toolset. A trusted execution host
can add dynamic sources. Request tool policy can only narrow the combined set.
Source specifications, definitions, calls, and results must stay portable.

Official MCP client support comes from `jido_connect` through
`Jido.AI.ToolSource`. This fixture models that boundary. It does not start an
MCP server, implement the protocol, or assign MCP ownership to Jido core.

## Limits

`Jido.AI.Skill` loads only `SKILL.md`. It does not execute scripts or load
other skill resources. The offline source does not prove MCP transport,
authentication, capability negotiation, reconnect, or cancellation.

## Core Fit and Gaps

The ToolSource contract cleanly separates trusted dynamic discovery and
execution from request data. Protocol-specific lifecycle, credentials, and
remote failure handling belong in `jido_connect` or another adapter package.

## Files

- [ToolSource](tool_sources.ex)
- [Skill fixture](fixtures/skills/focused-review/SKILL.md)
- [Tests](tool_sources_test.exs)

Previous: [Media Operations](../15_12_media_operations/README.md) |
Next: [Offline Testing](../15_14_offline_testing/README.md)
