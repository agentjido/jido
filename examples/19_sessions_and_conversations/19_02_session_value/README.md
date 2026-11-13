# 19_02 Session value

`Jido.Session` is an immutable portable value with one Thread. This lesson
appends a complete local exchange through `Jido.AI.Thread.Projection`, projects
messages, encodes and decodes JSON data, and closes the Session.

The [tests](session_value_test.exs)
also prove that a closed Session rejects a new append.

```sh
mix test.examples examples/19_sessions_and_conversations/19_02_session_value --warnings-as-errors
```

Previous: [Thread Agent](../19_01_thread_agent/README.md) | Next: [Session Agent](../19_03_session_agent/README.md)
