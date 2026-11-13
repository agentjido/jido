# 19_01 Thread Agent

A successful graph-first request creates a Session and appends user, model
attempt, assistant, and outcome entries to its Thread. Only complete user and
assistant exchanges enter later model context.

The [tests](thread_agent_test.exs)
check one completed exchange and one provider failure. The failed request has
an outcome record but no projected conversation pair.

```sh
mix test.examples examples/19_sessions_and_conversations/19_01_thread_agent --warnings-as-errors
```

Previous: [AI Basics](../../15_ai_agents/README.md) |
Next: [Session value](../19_02_session_value/README.md).
