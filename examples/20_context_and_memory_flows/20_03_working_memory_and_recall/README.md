# 20_03 Working memory and recall

This Flow builds structured application working memory and performs scoped
semantic recall through an application Action and offline embeddings.

## What you will learn

- How working memory stays in an application-owned portable map.
- How Agent, Session, resource, and tenant scope restrict recall.
- How recalled items keep provenance and a deterministic score.

## Read the code

Read [the working-memory and recall Flow](working_memory_and_recall.ex) first.

## Run it

`mix test.examples examples/20_context_and_memory_flows/20_03_working_memory_and_recall --warnings-as-errors`

Expected result: each tenant recalls only its fully scoped memory. An exact
offline embedding match has score `1.0` and keeps its source revision.

## Important behavior

The application owns working memory, scope rules, storage input, ranking, and
provenance. Recall does not read global Agent state or shared team memory. The
Flow output is a projection for one request.

## Limits

The two-value fixture embedding is not a production semantic model. In-memory
records do not prove vector-store consistency, deletion, or concurrent writes.

## Core Fit and Gaps

Normal Actions and the public inference-client embedding callback are
sufficient. Jido core does not need a Memory or Retriever API. A production
adapter must define storage consistency, authorization, and index refresh.

## Files

- [Source](working_memory_and_recall.ex)
- [Tests](working_memory_and_recall_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Trim and compact](../20_02_trim_and_compact/README.md)

[Next: Session rollover](../20_04_session_rollover/README.md)
