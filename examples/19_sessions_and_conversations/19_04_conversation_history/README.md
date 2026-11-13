# 19_04 Conversation history

The next request projects complete committed exchanges from Agent Session
state into ReqLLM context. The configured window limits included messages and
bytes without changing the stored Thread.

The [test](conversation_history_test.exs)
captures both offline model contexts and proves that the second call contains
the first user and assistant messages.

```sh
mix test.examples examples/19_sessions_and_conversations/19_04_conversation_history --warnings-as-errors
```

Previous: [Session Agent](../19_03_session_agent/README.md) | Next: [Request modes](../19_05_request_modes/README.md)
