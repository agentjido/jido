# 19_04 Conversation history and public UI projection

This lesson keeps two committed exchanges and converts them to a small
application-owned browser projection.

## What you will learn

- Later AI Turns project complete committed history from Session state.
- A public UI projection must select fields. It must not expose a complete
  AgentServer snapshot or internal Thread record.

## Read the code

Read [the Agent and public projection](conversation_history.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_04_conversation_history --warnings-as-errors`

Expected result: the public result contains two user and assistant pairs with
only `role` and `text` fields.

## Important behavior

The configured model-context window limits what one model call sees. It does
not delete stored Thread entries.

## Limits

The projection is intentionally small. A real LiveView must also authorize
the Session owner and apply its own content policy.

## Core Fit and Gaps

Public Session projection is sufficient. Jido cannot choose the correct
browser contract or authorization policy for an application.

## Files

- [Source](conversation_history.ex)
- [Tests](conversation_history_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: AI conversation projection](../19_03_session_agent/README.md)

[Next: Failed and incomplete exchanges](../19_05_request_modes/README.md)
