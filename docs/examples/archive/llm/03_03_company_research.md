> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Company Research Report

- **ID:** `03_03_company_research`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** true integration

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Collect company facts from several tools and produce a cited report.
- **User story:** As an analyst, I receive a concise company profile with source dates.
- **Trigger or input:** `research.company` Signal with company identity and report sections.
- **Agent state:** Research plan, source records, extracted facts, conflicts, report, and citations.
- **Actions or Flow:** A Flow plans queries, runs bounded searches, extracts facts, resolves conflicts, and writes the report.
- **External interactions:** Web search, page fetch, company data tools, and LLM. A local contract test uses saved fixtures.
- **Runtime Directives or capabilities:** Progress can use `Emit` Signals. A Dispatch Directive can store the final report after commit.
- **Expected result:** The report cites each material fact and marks unresolved conflicts.
- **Failure cases:** Wrong entity, stale source, access block, source conflict, model error, or budget limit.
- **Jido features under pressure:** Long effectful Flow, provenance, progress, budgets, and one terminal commit.
- **Source framework and links:** [AutoGen: company research](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/examples/company-research.html), [Mastra: deep research template](https://mastra.ai/docs)

## Best-effort implementation

- `git show 357b22a:examples/03_llm/03_03_company_research/company_research.ex`
- `git show 357b22a:test/examples/03_llm/03_03_company_research/company_research_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
