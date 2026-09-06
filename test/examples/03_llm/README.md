# LLM SDK integration examples

This batch has ten examples and 66 enabled tests. Run all ten:

```shell
mix test --include example test/examples/03_llm --seed 0
```

Append a numbered folder to run one fixture. The default test command excludes
the examples; every LLM example has the `:example` tag.

| Order | Added capability | Tests |
| --- | --- | ---: |
| [03_01_model_response](../../../docs/examples/profiles/03_llm/03_01_model_response.md) | One typed response, transient client context, selected persisted fields, and explicit fallback policy. | 4 |
| [03_02_conversation_history](../../../docs/examples/profiles/03_llm/03_02_conversation_history.md) | Actual history across Turns, duplicate rejection, and restore with a fresh client. | 2 |
| [03_03_tool_call](../../../docs/examples/profiles/03_llm/03_03_tool_call.md) | An approved name resolves to a typed Action; invalid input stops before tool effects. | 4 |
| [03_04_tool_loop](../../../docs/examples/profiles/03_llm/03_04_tool_loop.md) | Flow Dispatch and continuation carry model/tool rounds to one terminal commit. | 11 |
| [03_05_parallel_tools](../../../docs/examples/profiles/03_llm/03_05_parallel_tools.md) | Validate a complete tool plan, run concurrent Actions with Map, and retain call-ID order. | 5 |
| [03_06_grounded_answer](../../../docs/examples/profiles/03_llm/03_06_grounded_answer.md) | Retrieve evidence, generate an answer, and validate citation identity, revision, and page before commit. | 3 |
| [03_07_output_repair](../../../docs/examples/profiles/03_llm/03_07_output_repair.md) | Flow Iterate carries validation feedback through at most three model attempts. | 3 |
| [03_08_context_compaction](../../../docs/examples/profiles/03_llm/03_08_context_compaction.md) | Compact committed history and retain recent and queued messages under an explicit byte limit. | 2 |
| [03_09_subagent_delegation](../../../docs/examples/profiles/03_llm/03_09_subagent_delegation.md) | Spawn a real child Agent, transfer client context explicitly, and correlate result and failure Signals. | 6 |
| [03_10_recursive_analysis](../../../docs/examples/profiles/03_llm/03_10_recursive_analysis.md) | Run the bounded application recursion tree under one Agent execution lifecycle. | 26 |

`JidoTest.LLMSDKCase` supplies startup helpers and an external service recorder.
Barriers run in real execution workers, outside the recorder. They establish
actual overlap, order, and termination. ReAct and RLM keep their existing
adapter contracts and regression tests.

The suite proves local SDK integration. Fixed replies do not prove factual
accuracy, model quality, provider compatibility, image understanding, or a
model-specific token bound. The archive retains the unfinished Deep Research
requirements. See the [result report](../../../docs/examples/llm-results.md).
