# 15_05 Streaming

Set `stream: true` on a normal AI request. The model call emits ordered Jido
Signals for start, chunks, completion, or failure. The final materialized
response still commits one assistant message.

The [test](streaming_test.exs)
uses a local stream and checks Signal order, sequence numbers, reply output,
and committed Session state.

```sh
mix test.examples examples/15_ai_basics/15_05_streaming --warnings-as-errors
```

Previous: [Limits and tool policy](../15_04_controls/README.md) | Next: [Request contract](../15_06_request_contract/README.md)
