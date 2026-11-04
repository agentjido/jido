# 02_05 Request modes

Run one AI Agent through AgentServer. `call` and `submit` have a reply owner,
so the AI Reply Directive commits and returns. `cast` has no reply owner. The
current runtime drops this reply route before model work and keeps state unchanged.

The [test](../../../../test/examples/ai/02_conversations/02_05_request_modes/request_modes_test.exs)
checks call, submit and await, cast rejection, Session revisions, and cleanup.

```sh
mix test.examples test/examples/ai/02_conversations/02_05_request_modes --warnings-as-errors
```

Previous: [Conversation history](../02_04_conversation_history/README.md)
