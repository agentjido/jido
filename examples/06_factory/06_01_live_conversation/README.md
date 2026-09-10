# 06_01 Live Conversation

One Agent calls ReqLLM and commits only complete model replies to its text
history.

## What you will learn

- How conversation history belongs in Agent state.
- How provider options, credentials, and streaming callbacks stay in Turn context.

## Read the code

Read [the conversation Agent](conversation.ex), then the shared
[model loop](../support/model.ex) and [error formatter](../support/error.ex).

## Run it

```sh
mix test test/examples/06_factory/06_01_live_conversation --include example --seed 0
```

Expected result: successful replies extend history, duplicate request IDs are
rejected, and provider failure preserves the last commit.

## Important behavior

The model loop has fixed request and tool limits. A partial stream can be shown
to a terminal, but only a complete response enters Agent state.

## Limits

The test uses a local HTTP provider response. A live run needs a supported model
and provider key.

## Files

- [Source](conversation.ex)
- [Tests](../../../test/examples/06_factory/06_01_live_conversation/conversation_test.exs)
- [Model support](../support/model.ex)
- [Error support](../support/error.ex)

Previous: [Remote Lifecycle](../../05_multi_agent/05_05_remote_lifecycle/README.md) | Next: [Three-Agent System](../06_02_three_agent_system/README.md)
