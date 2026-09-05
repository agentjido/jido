> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Deep Research

- **ID:** `03_07_deep_research`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** true integration

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Run an open-ended but bounded research plan across many sources.
- **User story:** As a decision maker, I receive a detailed report with evidence, gaps, and a method record.
- **Trigger or input:** `research.deep` Signal with objective, constraints, source policy, and budget.
- **Agent state:** Plan, open questions, source ledger, notes, claims, report, budget use, and stop reason.
- **Actions or Flow:** A Flow iterates plan, search, fetch, analyze, and revise until exit criteria or budget stop.
- **External interactions:** Search, fetch, optional code tools, and LLMs. Local tests use a small replay dataset.
- **Runtime Directives or capabilities:** Progress Signals, scheduled continuation, child research Actors, and report storage.
- **Expected result:** The report is reproducible from the source ledger and stops within bounds.
- **Failure cases:** Runaway plan, duplicate search, weak sources, citation loss, budget overrun, or cancellation.
- **Jido features under pressure:** Long-running Flow, checkpoints, budgets, progress, child work, and recovery.
- **Source framework and links:** [Mastra: deep research example](https://mastra.ai/en/examples/deep-research), [AutoGen: company research](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/examples/company-research.html)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_07_deep_research/deep_research.ex`
- `git show 357b22a:test/examples/03_llm/03_07_deep_research/deep_research_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The replay adapter validates a finished research record. The full plan/search/fetch/revise loop and continuation are not implemented.

An example-scope gap is not evidence of a core Jido defect.
