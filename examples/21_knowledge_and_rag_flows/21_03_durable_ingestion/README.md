# 21_03 Durable ingestion and refresh

This durable Flow loads and chunks one document revision, creates offline
embeddings and an index update plan, waits for storage acknowledgement, and
then commits one result.

## What you will learn

- How loading, chunking, embedding, refresh deletion, and quality checks form a
  normal Flow.
- How stable chunk IDs and a document revision define idempotency.
- How `Jido.Durable` saves the plan and Wait before external acknowledgement.

## Read the code

Read [the ingestion Flow](durable_ingestion.ex) first.

## Run it

`mix test.examples examples/21_knowledge_and_rag_flows/21_03_durable_ingestion --warnings-as-errors`

Expected result: revision 2 plans two upserts and one deletion. The offline
index saves the plan, loses its first acknowledgement, and returns the same
acknowledgement on retry. The restarted Jido instance rejects a stale revision
and completes the original Wait when it receives the matching acknowledgement.

## Important behavior

The durable execution is the logical owner of the ingestion plan. The external
index is the canonical owner only after its acknowledgement. The commit Signal
must match document ID and revision. Stable chunk IDs make a repeated upsert
safe for an idempotent index adapter.

## Limits

ETS does not survive BEAM loss. The [offline index](index.ex) keeps one applied plan per revision key in memory.
The integration test drives the application side of that boundary. An index can acknowledge and later lose data. The
parent durable checkpoint is not an atomic checkpoint with the index.

## Core Fit and Gaps

Actions, inference-client embeddings, Flow Wait, and `Jido.Durable` compose
without a new ingestion or Retriever API. A production adapter must define
atomicity, acknowledgement, retry, and cleanup for its index.

- Logical owner: durable ingestion reference.
- Process owner: named Jido instance while active.
- Canonical state owner: durable plan before acknowledgement; external index
  after acknowledgement.
- Commit point: matching index acknowledgement Signal.
- Persisted data: document input, chunks, embeddings, update plan, Wait, and
  acknowledgement.
- Retry boundary: idempotent index upsert under one document-revision key.
- Idempotency rule: stable chunk IDs and `document_id:revision` key.
- Injected failure: the index loses its first acknowledgement and the Jido instance restarts at the Wait.
- Recovery result: the saved plan resumes from the same Wait.
- Limits and non-guarantees: no atomic checkpoint spans Jido and the index.

## Files

- [Source](durable_ingestion.ex)
- [Tests](durable_ingestion_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Agentic RAG tool](../21_02_agentic_rag_tool/README.md)
