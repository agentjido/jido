# 02_01 Thread Agent

A successful graph-first request creates a Session and appends user, model
attempt, assistant, and outcome entries to its Thread. Only complete user and
assistant exchanges enter later model context.

The [tests](../../../../test/examples/ai/02_conversations/02_01_thread_agent/thread_agent_test.exs)
check one completed exchange and one provider failure. The failed request has
an outcome record but no projected conversation pair.

```sh
mix test.examples test/examples/ai/02_conversations/02_01_thread_agent --warnings-as-errors
```

Next: [Session value](../02_02_session_value/README.md).
