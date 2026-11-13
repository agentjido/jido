# 19_05 Request modes

Run one AI Agent through AgentServer. `call` and `submit` have a reply owner,
so the AI Reply Directive commits and returns. `cast` has no reply owner. The
current runtime drops this reply route before model work and keeps state unchanged.

The [test](request_modes_test.exs)
checks call, submit and await, cast rejection, Session revisions, and cleanup.

```sh
mix test.examples examples/19_sessions_and_conversations/19_05_request_modes --warnings-as-errors
```

Previous: [Conversation history](../19_04_conversation_history/README.md) |
Next: [All Examples](../../README.md)
