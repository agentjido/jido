# 15_05 Streaming

Set `stream: true` on a normal AI request. The model call emits ordered Jido
Signals for start, chunks, completion, or failure. The final materialized
response still commits one assistant message.

## What you will learn

- How stream lifecycle Signals keep an explicit order and sequence.
- Why only final successful output enters the Session.

## Read the code

Read [the streaming Agent](agent.ex), then [the test](streaming_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_05_streaming --warnings-as-errors
```

Expected result: start, chunk, and completion Signals are ordered, and one
assistant message commits.

## Important behavior

A failed stream does not commit a partial assistant message.

## Limits

Stream chunks are transient delivery data. Only the final successful response
enters the Session, and a lost subscriber does not receive old chunks.

## Core Fit and Gaps

Streaming uses normal Signals and the same final Session commit boundary.
Transient chunks are intentionally outside durable Session history.

## Files

- [Streaming Agent](agent.ex)
- [Tests](streaming_test.exs)

Previous: [Limits and tool policy](../15_04_controls/README.md) | Next: [Request contract](../15_06_request_contract/README.md)
