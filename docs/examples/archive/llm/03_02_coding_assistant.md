> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Coding Assistant

- **ID:** `03_02_coding_assistant`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Inspect a small fixture repository, propose a patch, and run checks.
- **User story:** As a developer, I ask for one bounded code change and receive a verified patch.
- **Trigger or input:** `code.change` Signal with goal, allowed paths, and command policy.
- **Agent state:** Goal, file observations, proposed edits, command results, final patch, and status.
- **Actions or Flow:** A bounded Flow lets the model choose read, edit, and test tools under policy.
- **External interactions:** Filesystem, shell, and LLM. The local test uses a temporary fixture repository and fake model.
- **Runtime Directives or capabilities:** A supervised tool runtime can be a Plugin capability. Progress can use `Emit`.
- **Expected result:** Only allowed files change, checks pass, and the final patch is recorded.
- **Failure cases:** Path escape, unsafe command, failed test, context limit, bad patch, or cancellation.
- **Jido features under pressure:** Tool security, effectful Flow, sandbox policy, progress, and compensation limits.
- **Source framework and links:** [Pi: coding agent](https://github.com/earendil-works/pi/tree/main/packages/coding-agent), [LangGraph: code assistant](https://langchain-ai.github.io/langgraph/tutorials/code_assistant/langgraph_code_assistant/), [Mastra: coding template](https://mastra.ai/docs)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_02_coding_assistant/coding_assistant.ex`
- `git show 357b22a:test/examples/03_llm/03_02_coding_assistant/coding_assistant_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
