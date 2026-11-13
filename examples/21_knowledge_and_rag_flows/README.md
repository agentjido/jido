# 21 Knowledge and RAG Flows

These examples implement retrieval, generation, tool-driven retrieval, and
durable ingestion as normal Actions and Flows. Jido core does not add a
Retriever API.

## Examples

1. [Deterministic two-step RAG](21_01_two_step_rag/README.md).
2. [Agentic RAG tool](21_02_agentic_rag_tool/README.md).
3. [Durable ingestion and refresh](21_03_durable_ingestion/README.md).

The suite uses local documents, deterministic embeddings, and an offline model
client. No vector database or model provider is required.
