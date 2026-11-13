# 19_01 Thread values

This lesson builds and queries one immutable, append-only, portable `Jido.Thread`.

## What you will learn

- A Thread is a value. It does not own a process or storage adapter.
- Entries have stable sequence numbers, kinds, payloads, and references.

## Read the code

Read [the Thread builder](thread_agent.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_01_thread_agent --warnings-as-errors`

Expected result: two entries can be queried and survive a JSON data round-trip.

## Important behavior

Append returns a complete new Thread. It does not change the source value.

## Limits

A Thread does not save itself, serialize concurrent writers, or project one
feature-specific view.

## Core Fit and Gaps

The public Thread and Entry value APIs are sufficient. Storage ownership and
concurrent update policy belong to the application or Agent runtime.

## Files

- [Source](thread_agent.ex)
- [Tests](thread_agent_test.exs)

[Next: Session values](../19_02_session_value/README.md)
