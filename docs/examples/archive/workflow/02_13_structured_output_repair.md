> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Structured Output Repair

- **ID:** `02_13_structured_output_repair`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Repair invalid structured output with a fixed attempt limit.
- **User story:** As an application, I receive data that always matches the declared schema or a clear error.
- **Trigger or input:** `output.normalize` Signal with raw map or JSON data.
- **Agent state:** Validated value, attempt count, validation errors, and terminal status.
- **Actions or Flow:** A Flow parses, validates, applies allowed repairs, and validates again.
- **External interactions:** None for the base test. An LLM repair adapter can be added later.
- **Runtime Directives or capabilities:** None.
- **Expected result:** Valid output commits once. Exhausted repair returns a structured error and keeps prior state.
- **Failure cases:** Invalid JSON, missing field, unsafe coercion, unknown field, or attempt exhaustion.
- **Jido features under pressure:** Zoi-first contracts, bounded loops, validation details, and no partial state.
- **Source framework and links:** [Haystack: loop-based auto-correction pattern](https://docs.haystack.deepset.ai/docs/pipelines), [PydanticAI: output](https://pydantic.dev/docs/ai/core-concepts/output/)

## Burn-in result

The local example passes. A Flow Iterate validates and repairs one candidate
for at most three iterations. Safe repairs commit with prior validation
details. Exhaustion fails without a state change.

The Flow DSL requires `value([])` for an empty list in Iterate initial state.
A plain `[]` is rejected as an unsupported keyword expression.

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_13_structured_output_repair/structured_output_repair.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_13_structured_output_repair/structured_output_repair_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
