> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Codebase Review Tree

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_18_codebase_review_tree`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Review a large synthetic repository with a hierarchical Actor tree.
- **User story:** As a maintainer, I receive file findings, directory summaries, and one final report.
- **Trigger or input:** `review.start` Signal with repository manifest and review rules.
- **Agent state:** Tree manifest, assignments, finding IDs, summaries, progress, budget, and final report.
- **Actions or Flow:** Controllers split directory work, leaf Actors review fixtures, and parents reduce typed findings.
- **External interactions:** Fixture filesystem first; optional LLM and real repository later.
- **Runtime Directives or capabilities:** Spawn tree, targeted Signals, deadlines, progress, and complete cleanup.
- **Expected result:** Each file has one owner and each finding appears once in the root report.
- **Failure cases:** Tree too deep, worker crash, duplicate finding, context limit, or process limit.
- **Jido features under pressure:** About 1,500 Actors, hierarchy, scoped Bus traffic, reducers, persistence, and cleanup.
- **Source framework and links:** [Pi: coding agent](https://github.com/earendil-works/pi/tree/main/packages/coding-agent), [Akka: cluster sharding](https://doc.akka.io/libraries/akka-core/current/typed/cluster-sharding.html)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_18_codebase_review_tree/codebase_review_tree.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_18_codebase_review_tree/codebase_review_tree_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Logical file ownership and finding reduction work. The approximately 1,500-Actor tree and cleanup scenario are not implemented.

An example-scope gap is not evidence of a core Jido defect.
