# 15_09 JSON Agent

Encode and decode a graph-first AI Agent with `Jido.Codec`, `Jido.Agent.Codec`,
and an application-owned `Jido.Catalog`. The document stores versioned Agent,
Plugin, reasoning Flow, tool, and schema references. It stores no Elixir code.

The offline runner imports the fixture and compiles its root Flow. The
[tests](json_agent_test.exs)
check the fixture, a current JSON round trip, and untrusted-catalog rejection.

```sh
mix test.examples examples/15_ai_agents/15_09_json_agent --warnings-as-errors
mix run examples/15_ai_agents/15_09_json_agent/run.exs
```

Previous: [Model defaults](../15_08_model_helpers/README.md) |
Next: [AI Conversations](../../19_sessions_and_conversations/README.md)
