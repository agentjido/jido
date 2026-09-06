> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Spreadsheet Analysis

- **ID:** `02_12_spreadsheet_analysis`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** true integration

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Answer a business question from a spreadsheet and produce a typed report.
- **User story:** As an operator, I select a sheet and receive metrics, anomalies, and a concise explanation.
- **Trigger or input:** `sheet.analyze` Signal with sheet reference, range, and question.
- **Agent state:** Source revision, selected range, computed metrics, findings, and chart specification.
- **Actions or Flow:** A Flow reads cells, validates types, computes metrics, and generates the report.
- **External interactions:** Live spreadsheet API and optional model. A local contract test uses table fixtures.
- **Runtime Directives or capabilities:** A Plugin Directive can write an output tab or comment after commit.
- **Expected result:** The report names the source revision and matches calculated values.
- **Failure cases:** Auth error, missing range, mixed types, stale revision, formula error, or write conflict.
- **Jido features under pressure:** External read and write adapters, optimistic version, structured chart data, and secrets.
- **Source framework and links:** [Mastra: Google Sheet Analysis template](https://mastra.ai/docs)

## Burn-in result

The local adapter contract passes. The Flow reads an exact revision, validates
business rows, computes metrics, and builds a portable chart specification. A
stale revision prevents commit. No live spreadsheet service test is included.

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_12_spreadsheet_analysis/spreadsheet_analysis.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_12_spreadsheet_analysis/spreadsheet_analysis_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
