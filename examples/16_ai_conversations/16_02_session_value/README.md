# 16_02 Session value

`Jido.Session` is an immutable portable value with one Thread. This lesson
appends a complete local exchange through `Jido.AI.Thread.Projection`, projects
messages, encodes and decodes JSON data, and closes the Session.

The [tests](../../../test/examples/16_ai_conversations/16_02_session_value/session_value_test.exs)
also prove that a closed Session rejects a new append.

```sh
mix test.examples test/examples/16_ai_conversations/16_02_session_value --warnings-as-errors
```

Previous: [Thread Agent](../16_01_thread_agent/README.md) | Next: [Session Agent](../16_03_session_agent/README.md)
