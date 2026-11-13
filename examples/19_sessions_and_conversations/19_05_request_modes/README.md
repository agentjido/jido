# 19_05 Failed and incomplete exchanges

This lesson keeps failed and incomplete request evidence in the Thread while
excluding unsafe messages from later model context.

## What you will learn

- A failed request outcome does not erase its Thread evidence.
- An assistant tool request is incomplete until every named tool call has a
  matching tool result.

## Read the code

Read [the two exchange builders](failed_and_incomplete.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_05_request_modes --warnings-as-errors`

Expected result: the projection explains `request_not_completed` and
`incomplete_tool_exchange` exclusions.

## Important behavior

Projection is conservative. Evidence remains in the canonical Thread, but an
unsafe partial exchange does not become model context.

## Limits

This lesson does not retry or repair a failed model or tool call.

## Core Fit and Gaps

The public projection explanation makes exclusions observable. Recovery policy
and user-visible error text remain application concerns.

## Files

- [Source](failed_and_incomplete.ex)
- [Tests](failed_and_incomplete_test.exs)

[Previous: Conversation history](../19_04_conversation_history/README.md)

[Next: Concurrent request modes](../19_06_request_modes/README.md)
