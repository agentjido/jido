> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Hybrid Search

- **ID:** `02_04_hybrid_search`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Combine lexical and semantic search results with stable ranking.
- **User story:** As a user, I receive relevant results when exact terms and meaning both matter.
- **Trigger or input:** `search.hybrid` Signal with query and ranking options.
- **Agent state:** Candidate result IDs, component scores, final rank, and search settings.
- **Actions or Flow:** A Flow runs two retrievers, joins candidates, normalizes scores, and reranks them.
- **External interactions:** Lexical and vector retrievers. Local tests use fixed result fixtures.
- **Runtime Directives or capabilities:** None.
- **Expected result:** The same inputs produce the same ordered results in the local test.
- **Failure cases:** One retriever fails, score is invalid, duplicate candidate, join limit, or no result.
- **Jido features under pressure:** Parallel or sequential Flow steps, reducers, deterministic ordering, and partial failure policy.
- **Source framework and links:** [Haystack: hybrid retrieval tutorial](https://haystack.deepset.ai/tutorials/33_hybrid_retrieval)

## Burn-in result

The local example passes. Two independent retrieval steps can run in the same
Flow wave. One Action validates scores, joins duplicate candidates, applies
weights, and produces a stable rank. Partial results require an explicit
policy.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_04_hybrid_search/hybrid_search.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_04_hybrid_search/hybrid_search_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
