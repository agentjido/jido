# 16_01 Thread Agent

A successful graph-first request creates a Session and appends user, model
attempt, assistant, and outcome entries to its Thread. Only complete user and
assistant exchanges enter later model context.

The [tests](../../../test/examples/16_ai_conversations/16_01_thread_agent/thread_agent_test.exs)
check one completed exchange and one provider failure. The failed request has
an outcome record but no projected conversation pair.

```sh
mix test.examples test/examples/16_ai_conversations/16_01_thread_agent --warnings-as-errors
```

Previous: [AI Basics](../../15_ai_basics/README.md) |
Next: [Session value](../16_02_session_value/README.md).
