# 19_07 Persistence and restoration

This lesson snapshots and restores an AI Agent with its complete committed Session.

## What you will learn

- `Jido.Persistence.snapshot/2` captures portable Agent definition and state.
- Restore uses the saved definition and retains the Session and Thread.

## Read the code

Read [the restorable Agent and application boundary](persistence_and_restoration.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_07_persistence_and_restoration --warnings-as-errors`

Expected result: the restored Agent equals the candidate Agent and projects the
same user and assistant messages.

## Important behavior

The commit point is the successful pure Agent Turn. Snapshot runs after that
commit and contains Agent state, including the Session.

## Limits

This lesson does not write a storage adapter or recover a process. Chapter 12
and Chapter 13 test stored records and durable activation.

## Core Fit and Gaps

- Logical owner: the Agent ID.
- Process owner: none in this pure execution lesson.
- Canonical state owner: the Agent value.
- Commit point: the successful `Agent.cmd/3` result.
- Persisted data: one in-memory portable snapshot.
- Retry boundary: none.
- Idempotency rule: snapshot does not change Agent state.
- Injected failure: none.
- Recovery result: exact Agent and Session restoration.
- Non-guarantees: no adapter durability or process recovery claim.

The public snapshot boundary is sufficient. Storage selection and record
revision conflicts are separate runtime concerns.

## Files

- [Source](persistence_and_restoration.ex)
- [Tests](persistence_and_restoration_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Concurrent request modes](../19_06_request_modes/README.md)

[Next: Non-AI Session use](../19_08_non_ai_session/README.md)
