> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Self-Evaluation Loop

- **ID:** `03_16_self_evaluation_loop`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Improve a generated result against explicit criteria.
- **User story:** As a user, I receive an answer that passed a defined quality threshold.
- **Trigger or input:** `content.refine` Signal with prompt, rubric, threshold, and attempt limit.
- **Agent state:** Draft versions, rubric scores, feedback, attempt count, and selected result.
- **Actions or Flow:** A Flow generates, evaluates, and revises until the threshold or limit.
- **External interactions:** Generator and evaluator models. Local tests use fixed score sequences.
- **Runtime Directives or capabilities:** None.
- **Expected result:** The best valid draft commits with its score history and stop reason.
- **Failure cases:** Invalid score, evaluator disagreement, no improvement, model error, or limit reached.
- **Jido features under pressure:** Bounded model loop, state growth, score schema, deterministic fake model, and policy.
- **Source framework and links:** [CrewAI: self-evaluation loop Flow](https://github.com/crewAIInc/crewAI-examples/tree/main/flows/self_evaluation_loop_flow)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_16_self_evaluation_loop/self_evaluation_loop.ex`
- `git show 357b22a:test/examples/03_llm/03_16_self_evaluation_loop/self_evaluation_loop_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
