> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Metadata-Filtered Search

- **ID:** `02_07_metadata_filtered_search`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Apply access and metadata filters before retrieval.
- **User story:** As a user, I search only documents that my tenant and role can access.
- **Trigger or input:** `search.filtered` Signal with query, tenant, role, and filter values.
- **Agent state:** Normalized query, effective filters, result IDs, and policy decision.
- **Actions or Flow:** One Action builds a safe filter and calls an injected retriever.
- **External interactions:** Retriever or document store. The local test uses an in-memory index.
- **Runtime Directives or capabilities:** None for a synchronous query.
- **Expected result:** Every result matches the filter and access policy.
- **Failure cases:** Invalid filter, unsupported operator, tenant mismatch, retriever timeout, or empty result.
- **Jido features under pressure:** Security context, schema validation, adapter call, result verification, and sensitive data rules.
- **Source framework and links:** [Haystack: metadata filtering tutorial](https://haystack.deepset.ai/tutorials/31_metadata_filtering)

## Burn-in result

The local example passes. One Action builds mandatory tenant and role filters,
calls an in-memory retriever, and verifies returned records against the same
policy. Unsupported filter operators fail before commit.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_07_metadata_filtered_search/metadata_filtered_search.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_07_metadata_filtered_search/metadata_filtered_search_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
