# 20 Context and Memory Flows

These examples implement context assembly, history management, working memory,
recall, and Session rollover as normal Jido Flows. Jido core does not add a
Memory or Retriever API.

## Examples

1. [Context assembly](20_01_context_assembly/README.md).
2. [Trim and compact](20_02_trim_and_compact/README.md).
3. [Working memory and recall](20_03_working_memory_and_recall/README.md).
4. [Session rollover](20_04_session_rollover/README.md).

All model and embedding operations use deterministic offline inference. The
examples name the owner and provenance of every context layer.
