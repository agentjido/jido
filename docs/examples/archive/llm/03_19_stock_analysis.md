> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Stock Analysis Report

- **ID:** `03_19_stock_analysis`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** true integration

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Build a dated research report from market and company data.
- **User story:** As an analyst, I receive a report that separates facts, calculations, and model commentary.
- **Trigger or input:** `finance.stock.analyze` Signal with ticker, date, and metric set.
- **Agent state:** Source timestamps, price data, financial metrics, calculations, report, and warnings.
- **Actions or Flow:** A Flow fetches data, calculates metrics, validates dates, and generates commentary.
- **External interactions:** Market and financial data APIs plus optional model. Local tests use historical fixtures.
- **Runtime Directives or capabilities:** A scheduled Signal can refresh the report. Audit storage can use a Plugin Directive.
- **Expected result:** All figures tie to source values and no stale figure appears as current.
- **Failure cases:** Bad ticker, market holiday, stale data, provider conflict, calculation error, or rate limit.
- **Jido features under pressure:** Temporal data, source policy, external adapters, schedules, and disclaimer metadata.
- **Source framework and links:** [CrewAI: stock analysis crew](https://github.com/crewAIInc/crewAI-examples/tree/main/crews/stock_analysis)

## Best-effort implementation

- `git show 357b22a:lib/examples/03_llm/03_19_stock_analysis/stock_analysis.ex`
- `git show 357b22a:test/examples/03_llm/03_19_stock_analysis/stock_analysis_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
