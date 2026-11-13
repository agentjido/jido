# 19_02 Session values

This lesson records, projects, encodes, decodes, and closes one portable Session.

## What you will learn

- A Session owns one Thread and adds status, metadata, and a Session revision.
- Closing an immutable Session prevents later append operations.

## Read the code

Read [the Session operations](session_value.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_02_session_value --warnings-as-errors`

Expected result: one complete exchange survives a JSON data round-trip, and a
closed Session rejects a new message.

## Important behavior

The Session is portable data. The caller remains responsible for storing the
returned value.

## Limits

This lesson does not start an Agent or write a persistence adapter.

## Core Fit and Gaps

Session lifecycle and codec operations compose cleanly. Concurrent writers
still need an AgentServer or application compare-and-swap policy.

## Files

- [Source](session_value.ex)
- [Tests](session_value_test.exs)

[Previous: Thread values](../19_01_thread_agent/README.md)

[Next: AI conversation projection](../19_03_session_agent/README.md)
