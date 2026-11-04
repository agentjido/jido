# 01_09 JSON Agent

Encode and decode a graph-first AI Agent with `Jido.Codec`, `Jido.Agent.Codec`,
and an application-owned `Jido.Catalog`. The document stores versioned Agent,
Plugin, reasoning Flow, tool, and schema references. It stores no Elixir code.

The offline runner imports the fixture and compiles its root Flow. The
[tests](../../../../test/examples/ai/01_basics/01_09_json_agent/json_agent_test.exs)
check the fixture, a current JSON round trip, and untrusted-catalog rejection.

```sh
mix test.examples test/examples/ai/01_basics/01_09_json_agent --warnings-as-errors
mix run examples/ai/01_basics/01_09_json_agent/run.exs
```

Previous: [Model defaults](../01_08_model_helpers/README.md) | Next: [Conversations](../../02_conversations/README.md)
