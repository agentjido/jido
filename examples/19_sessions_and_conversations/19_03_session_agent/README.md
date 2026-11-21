# 19_03 AI conversation projection

This lesson runs one offline AI Turn and projects its committed Session into
the complete messages that a later model call can see.

## What you will learn

- The AI Agent owns the canonical Session in portable Agent state.
- AI projection includes completed user and assistant messages and excludes
  feature observations.

## Read the code

Read [the Session Agent](session_agent.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_03_session_agent --warnings-as-errors`

Expected result: the first successful offline Turn creates a Session and
projects one complete user and assistant exchange.

## Important behavior

The projection reads committed Session state. It does not read provider state
or private AgentServer process state.

## Limits

This lesson does not test history windows, persistence, or concurrent requests.

## Core Fit and Gaps

The AI Agent, Session, and public Thread projection compose cleanly. The
application must still decide which projection is safe for each external UI.

## Files

- [Source](session_agent.ex)
- [Tests](session_agent_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Session values](../19_02_session_value/README.md)

[Next: Conversation history](../19_04_conversation_history/README.md)
