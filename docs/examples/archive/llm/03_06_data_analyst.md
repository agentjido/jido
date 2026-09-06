> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Data Analyst

- **ID:** `03_06_data_analyst`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Use code or table tools to answer a question from a dataset.
- **User story:** As an analyst, I upload a bounded table and receive calculations plus a clear answer.
- **Trigger or input:** `data.analyze` Signal with dataset ID and question.
- **Agent state:** Dataset digest, plan, tool calls, outputs, charts, answer, and warnings.
- **Actions or Flow:** A ReAct-style Flow runs safe table operations or sandboxed code and validates the result.
- **External interactions:** Code sandbox and LLM. Local tests use a fixed table tool without arbitrary code.
- **Runtime Directives or capabilities:** A Plugin can own sandbox lifecycle and cleanup commands.
- **Expected result:** The answer references computed values and reproducible operations.
- **Failure cases:** Unsafe code, missing column, numeric error, output limit, sandbox timeout, or model error.
- **Jido features under pressure:** Tool policy, sandbox runtime, result schemas, resource limits, and cleanup.
- **Source framework and links:** [PydanticAI: data analyst](https://pydantic.dev/docs/ai/examples/data-analytics/data-analyst/), [Google ADK: code execution tool](https://google.github.io/adk-docs/tools/google-cloud/code-exec-agent-engine/)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_06_data_analyst/data_analyst.ex`
- `git show 357b22a:test/examples/03_llm/03_06_data_analyst/data_analyst_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
