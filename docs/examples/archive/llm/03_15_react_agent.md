> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# ReAct Agent

- **ID:** `03_15_react_agent`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Show one effectful ReAct Flow with one successful terminal Actor commit.
- **User story:** As a user, I ask one question, the agent searches once, and I receive one answer.
- **Trigger or input:** One Signal with the user question.
- **Agent state:** `messages`, `last_answer`, and `turns`.
- **Actions or Flow:** One Signal runs one Flow. A `ScriptedModel` returns one tool call and then one answer. A local `SearchTool` records its effect.
- **External interactions:** The effectful Flow calls the scripted model twice and the local search tool once on success.
- **Runtime Directives or capabilities:** None in the current example. The model and tool effects occur inside the Flow.
- **Expected result:** Success calls the model twice and the tool once, then commits Actor state and version one time.
- **Failure cases:** Model error after a tool call, unknown tool, tool failure, malformed model output, provider timeout, exhausted step budget, and active Turn cancellation.
- **Jido features under pressure:** Effectful Flow execution, repeated tool-result routing, bounded continuation, cancellation, one terminal commit, and clear pre-commit effect semantics.
- **Source framework and links:** [LlamaIndex: ReAct workflow](https://developers.llamaindex.ai/python/examples/workflow/react_agent/), `git show 357b22a:lib/examples/03_llm/03_15_react_agent/react_agent.ex`, and `git show 357b22a:test/examples/03_llm/03_15_react_agent/react_agent_test.exs`

## Burn-in result

Nine local tests pass. Several model and tool calls remain inside one Actor
Turn and produce one terminal commit. Every tested failure keeps Actor state
unchanged while preserving the external calls that already completed. The
application carries a finite model-step budget through the Flow. Actor Server
cancellation stops a blocked model task.

Message history is ordinary Actor state. This example does not need a
Scheduler Plugin.

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_15_react_agent/react_agent.ex`
- `git show 357b22a:test/examples/03_llm/03_15_react_agent/react_agent_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
