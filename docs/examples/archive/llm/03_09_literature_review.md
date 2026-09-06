> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Literature Review

- **ID:** `03_09_literature_review`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** true integration

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Search papers, extract evidence, and synthesize a cited review.
- **User story:** As a researcher, I receive a structured review for a focused question.
- **Trigger or input:** `research.literature` Signal with question, date range, and result limit.
- **Agent state:** Search plan, paper metadata, evidence notes, themes, report, and citations.
- **Actions or Flow:** A Flow searches, deduplicates papers, extracts claims, groups themes, and writes the review.
- **External interactions:** Scholarly search, paper fetch, and LLM. Local tests use citation fixtures.
- **Runtime Directives or capabilities:** Progress Signals and final report storage can use Plugin Directives.
- **Expected result:** The report includes only retrieved papers and preserves identifiers.
- **Failure cases:** Duplicate paper, inaccessible text, bad metadata, unsupported claim, or search budget limit.
- **Jido features under pressure:** Deduplication, evidence state, large Flow, rate limits, and citation integrity.
- **Source framework and links:** [AutoGen: literature review](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/examples/literature-review.html)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_09_literature_review/literature_review.ex`
- `git show 357b22a:test/examples/03_llm/03_09_literature_review/literature_review_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
