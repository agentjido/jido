# 20_04 Session rollover

This one-step Flow closes a long-running Session and creates a linked Session
that starts with a lossy summary and explicit lineage.

## What you will learn

- How a single Action uses the same execution model as a one-step Flow.
- How an expected revision prevents a concurrent stale rollover.
- How encoded Session documents support application persistence and replay.

## Read the code

Read [the rollover Action and Flow](session_rollover.ex) first.

## Run it

`mix test.examples examples/20_context_and_memory_flows/20_04_session_rollover --warnings-as-errors`

Expected result: the old Session is closed with full history, the new Session
has one summary entry and lineage, and a stale expected revision is rejected.

## Important behavior

The application is the logical and canonical owner of both Session documents.
The Action returns complete candidate documents. Saving them is a separate
application commit. The summary records its source Session and revision, but
it is not a complete replay of the source history.

## Limits

This example proves portable encode and decode, not an atomic storage
transaction across two Session documents. It does not resolve two concurrent
writers after both read the same revision. The summary can omit important
facts.

## Core Fit and Gaps

Portable Session values and a normal Flow are sufficient for rollover logic.
The application persistence layer must provide compare-and-swap if it needs an
atomic revision check and write. Jido does not imply that closing the parent
creates a coordinated checkpoint of other Agents or resources.

- Logical owner: application Session ID.
- Process owner: none in this pure Flow.
- Canonical state owner: the application persistence record after commit.
- Commit point: application compare-and-swap of the returned documents.
- Persisted data: closed source Session, new Session, summary, and lineage.
- Retry boundary: one compare-and-swap attempt at the expected revision.
- Idempotency rule: new Session ID and source revision identify one rollover.
- Injected failure: stale expected revision.
- Recovery result: no candidate document is returned for stale input.
- Limits and non-guarantees: the example has no two-record atomic store.

## Files

- [Source](session_rollover.ex)
- [Tests](session_rollover_test.exs)

[Previous: Working memory and recall](../20_03_working_memory_and_recall/README.md)
