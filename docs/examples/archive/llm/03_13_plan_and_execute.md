> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Plan and Execute

- **ID:** `03_13_plan_and_execute`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Separate a task plan from bounded step execution.
- **User story:** As a user, I give a multi-step goal and receive a result plus the completed plan.
- **Trigger or input:** `plan.execute` Signal with goal and step limit.
- **Agent state:** Goal, plan steps, current step, observations, revised plan, and terminal result.
- **Actions or Flow:** A Flow asks for a typed plan, executes allowed steps, and optionally revises remaining work.
- **External interactions:** Planner model, executor tools, and optional final model. Local tests use fixtures.
- **Runtime Directives or capabilities:** None in the single-turn form. Long work can schedule a continuation Signal.
- **Expected result:** Every executed step maps to the plan and the run stops within the limit.
- **Failure cases:** Invalid plan, forbidden tool, failed step, endless revision, or budget limit.
- **Jido features under pressure:** Nested data schemas, dynamic Flow loop, tool policy, and termination.
- **Source framework and links:** [LangGraph: workflows and agents](https://docs.langchain.com/oss/python/langgraph/workflows-agents)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_13_plan_and_execute/plan_and_execute.ex`
- `git show 357b22a:test/examples/03_llm/03_13_plan_and_execute/plan_and_execute_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
