# 16_03 Session Agent

`Jido.AI.Agent` owns a nullable Session field. The first successful request
creates and commits the Session. The complete Agent remains portable through
the normal persistence snapshot and restore boundary.

The [test](session_agent_test.exs)
checks the first commit and exact snapshot restore.

```sh
mix test.examples examples/16_ai_conversations/16_03_session_agent --warnings-as-errors
```

Previous: [Session value](../16_02_session_value/README.md) | Next: [Conversation history](../16_04_conversation_history/README.md)
