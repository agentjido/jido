> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Conditional Fallback

- **ID:** `02_01_conditional_fallback`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Show typed routing from a primary operation to a safe fallback.
- **User story:** As a user, I still receive a useful result when the preferred source is unavailable.
- **Trigger or input:** `lookup.run` Signal with query and fallback policy.
- **Agent state:** Query, selected route, result, attempts, and warning list.
- **Actions or Flow:** A Flow tries the primary adapter, classifies its error, and uses the fallback only for allowed errors.
- **External interactions:** Primary and fallback data sources. Both use fake adapters in the local test.
- **Runtime Directives or capabilities:** An optional Audit Plugin Directive records the selected route after commit.
- **Expected result:** The state identifies the source and does not hide a degraded result.
- **Failure cases:** Permanent primary error, fallback error, bad error classification, or both sources return invalid data.
- **Jido features under pressure:** Conditional Flow routing, error types, adapter policy, warnings, and one commit.
- **Source framework and links:** [Haystack: pipelines and conditional routing](https://docs.haystack.deepset.ai/docs/pipelines)

## Burn-in result

The local example passes. A Choice selects the primary result, an allowed
fallback, or a terminal error. Expected provider errors must first become
successful Action data because a Choice fallback is not an error handler.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_01_conditional_fallback/conditional_fallback.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_01_conditional_fallback/conditional_fallback_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
