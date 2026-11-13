# 21_01 Deterministic two-step RAG

This Flow retrieves and reranks local documents, generates one offline answer,
assembles citations, and applies retrieval and answer quality gates.

## What you will learn

- How retrieval and generation remain separate Actions.
- How source revision and ranking data follow the answer.
- How quality gates stop empty retrieval or uncited output.

## Read the code

Read [the three-stage RAG Flow](two_step_rag.ex) first.

## Run it

`mix test.examples examples/21_knowledge_and_rag_flows/21_01_two_step_rag --warnings-as-errors`

Expected result: one policy document produces an answer with `[doc-1]` and its
revision. An unrelated query stops before model generation.

## Important behavior

Retrieval is deterministic. Reranking and generation use the offline inference
client. Citation IDs come from retrieved records, not from model text alone.
The final gate verifies that the answer names a known citation.

## Limits

Term overlap and fixture reranking are not production search quality. A valid
citation marker does not prove that the cited source supports every claim.

## Core Fit and Gaps

Actions, Flow ordering, and the inference-client callbacks compose cleanly.
Storage and retrieval remain application concerns. Jido core does not need a
Retriever API for this pattern.

## Files

- [Source](two_step_rag.ex)
- [Tests](two_step_rag_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Next: Agentic RAG tool](../21_02_agentic_rag_tool/README.md)
