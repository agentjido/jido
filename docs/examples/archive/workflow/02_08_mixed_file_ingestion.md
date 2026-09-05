> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Mixed File Ingestion

- **ID:** `02_08_mixed_file_ingestion`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Route several file types through the correct converter.
- **User story:** As a knowledge-base owner, I ingest text, PDF, and HTML fixtures in one request.
- **Trigger or input:** `documents.ingest` Signal with file descriptors and content digests.
- **Agent state:** Per-file status, normalized document IDs, extracted metadata, and errors.
- **Actions or Flow:** A Flow classifies each file, runs its converter, normalizes documents, and joins results.
- **External interactions:** File readers and converters. Tests use small fixture files and fake PDF output.
- **Runtime Directives or capabilities:** A Dispatch Plugin Directive can write final documents to an external index after commit.
- **Expected result:** Supported files have stable document records and unsupported files have explicit errors.
- **Failure cases:** Unknown type, corrupt content, converter timeout, duplicate document, or mixed partial failure.
- **Jido features under pressure:** Branching, batch results, portable state, partial-result policy, and external write boundary.
- **Source framework and links:** [Haystack: file type preprocessing tutorial](https://haystack.deepset.ai/tutorials/30_file_type_preprocessing_index_pipeline)

## Burn-in result

The local example passes. A Flow Map uses `on_error: :collect_errors` so text,
HTML, PDF, and unsupported files produce one ordered batch result. Supported
documents and explicit per-file errors commit together.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_08_mixed_file_ingestion/mixed_file_ingestion.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_08_mixed_file_ingestion/mixed_file_ingestion_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
