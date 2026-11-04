# 16_04 Conversation history

The next request projects complete committed exchanges from Agent Session
state into ReqLLM context. The configured window limits included messages and
bytes without changing the stored Thread.

The [test](../../../test/examples/16_ai_conversations/16_04_conversation_history/conversation_history_test.exs)
captures both offline model contexts and proves that the second call contains
the first user and assistant messages.

```sh
mix test.examples test/examples/16_ai_conversations/16_04_conversation_history --warnings-as-errors
```

Previous: [Session Agent](../16_03_session_agent/README.md) | Next: [Request modes](../16_05_request_modes/README.md)
