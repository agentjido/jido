# 03_02 Conversation history

This example keeps portable conversation history across Agent Turns.

## What you will learn

- How an inline Action builds model input from committed Agent state.
- How message IDs reject duplicate work before the model call.

## Read the code

Read [the Agent](conversation_history.ex), then the shared
[LLM adapter contract](../support/adapter.ex).

## Run it

```sh
mix test test/examples/03_llm/03_02_conversation_history --include example --seed 0
```

Expected result: each new Turn sends the complete prior history, and restored
state works with a fresh runtime client.

## Important behavior

Messages and processed IDs are portable Agent state. The model client is Turn
context and is not persisted. A duplicate ID or provider error preserves the
last committed history.

## Limits

This example does not compact history or define a provider token format.

## Files

- [Agent and inline Action](conversation_history.ex)
- [Shared LLM adapter](../support/adapter.ex)
- [Tests](../../../test/examples/03_llm/03_02_conversation_history/conversation_history_test.exs)

Previous: [Model Response](../03_01_model_response/README.md) | Next: [Tool Call](../03_03_tool_call/README.md)
