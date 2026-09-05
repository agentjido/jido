> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Research Team

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_07_research_team`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Split a research question among source, analysis, and writing specialists.
- **User story:** As a researcher, I receive one cited report built from independent evidence tasks.
- **Trigger or input:** `research.team.run` Signal with question, source pack, and limits.
- **Agent state:** Research plan, assignments, source ledger, specialist results, conflicts, and report.
- **Actions or Flow:** A supervisor delegates bounded work in parallel, joins evidence, and runs a writer-reviewer Flow.
- **External interactions:** Search and model tools. The local test uses a fixed evidence pack and fake Agents.
- **Runtime Directives or capabilities:** Child lifecycle, task Signals, progress Signals, deadlines, and cleanup.
- **Expected result:** The report preserves source ownership, resolves duplicates, and cites every material claim.
- **Failure cases:** Duplicate source, specialist timeout, conflicting evidence, weak citation, or budget limit.
- **Jido features under pressure:** Fan-out, join, source provenance, context isolation, and long-run cleanup.
- **Source framework and links:** [AutoGen: company research](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/examples/company-research.html), [CrewAI: crews](https://docs.crewai.com/en/concepts/crews)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_07_research_team/research_team.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_07_research_team/research_team_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Source ownership, deduplication, and citations work. Parallel child Actors, deadlines, and cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
