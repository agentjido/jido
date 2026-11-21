# 15_09 JSON Agent

Encode and decode a graph-first AI Agent with `Jido.Codec`, `Jido.Agent.Codec`,
and an application-owned `Jido.Catalog`. The document stores versioned Agent,
Plugin, reasoning Flow, tool, and schema references. It stores no Elixir code.

## What you will learn

- How an AI Agent definition becomes a trusted JSON document.
- How Catalog resolution protects executable references.

## Read the code

Read [the JSON Agent](json_agent.ex), then [the runner](run.exs), and then
[the tests](json_agent_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_09_json_agent --warnings-as-errors
mix run examples/15_ai_agents/15_09_json_agent/run.exs
```

Expected result: the fixture and current encoder round-trip to the same
definition, while an empty Catalog rejects the document.

## Important behavior

The runner imports the fixture and compiles the root Flow without a provider
call.

## Limits

The document stores trusted references, not Elixir code or provider
credentials. Import requires an application-owned Catalog with compatible
targets.

## Core Fit and Gaps

Agent, Plugin, reasoning Flow, tool, schema, Catalog, and Codec contracts
compose into one portable definition boundary. No new AI document API is
needed.

## Files

- [JSON Agent](json_agent.ex)
- [Runner](run.exs)
- [Tests](json_agent_test.exs)

Previous: [Model defaults](../15_08_model_helpers/README.md) |
Next: [AI Conversations](../../19_sessions_and_conversations/README.md)
