# 21_02 Agentic RAG tool

This ReAct Agent selects a normal retrieval Action, records the tool result in
its Session, and returns an offline cited answer.

## What you will learn

- How agentic RAG uses an Action or Flow tool, not a second retrieval runtime.
- How model and tool rounds stay bounded.
- How source identity and revision survive the tool boundary.

## Read the code

Read [the retrieval Action and Agent](agentic_rag_tool.ex), then read the
[offline tool client](../support/rag_tool_client.ex).

## Run it

`mix test.examples examples/21_knowledge_and_rag_flows/21_02_agentic_rag_tool --warnings-as-errors`

Expected result: one model tool request runs `rag_lookup_policy`; the second
model round returns a cited answer. The Session contains the source revision.

## Important behavior

The model chooses whether to call the visible retrieval tool. ReAct enforces
one tool round and two model calls. The Action owns retrieval data and the
Session owns the recorded tool exchange.

## Limits

The fixture always requests one known tool. It does not measure retrieval
quality or prove that the final answer follows the returned evidence.

## Core Fit and Gaps

The normal AI tool contract is sufficient for agentic RAG. The application
owns retrieval, storage, authorization, and citations. Jido core does not own
an MCP or Retriever implementation for this example.

## Files

- [Source](agentic_rag_tool.ex)
- [Tests](agentic_rag_tool_test.exs)
- [Offline tool client](../support/rag_tool_client.ex)

[Previous: Two-step RAG](../21_01_two_step_rag/README.md)

[Next: Durable ingestion](../21_03_durable_ingestion/README.md)
