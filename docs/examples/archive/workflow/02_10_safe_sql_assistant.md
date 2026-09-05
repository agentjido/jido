> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Safe SQL Assistant

- **ID:** `02_10_safe_sql_assistant`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Turn a question into a read-only SQL query and a typed answer.
- **User story:** As an analyst, I ask about a small database without writing SQL.
- **Trigger or input:** `sql.question` Signal with question and allowed schema.
- **Agent state:** Question, generated query, validation result, rows, and answer.
- **Actions or Flow:** A Flow generates or receives SQL, validates read-only policy, executes it, and formats rows.
- **External interactions:** Model and SQL database. The local test uses fixed model output and in-memory data.
- **Runtime Directives or capabilities:** None for the query. An Audit Directive can record the approved query after commit.
- **Expected result:** Only allowed SQL runs, and query plus result commit one time.
- **Failure cases:** Unsafe statement, unknown table, invalid query, timeout, too many rows, or model error.
- **Jido features under pressure:** Effectful Flow steps, policy guard, typed data, secrets, and idempotent read behavior.
- **Source framework and links:** [PydanticAI: SQL generation](https://pydantic.dev/docs/ai/examples/data-analytics/sql-gen/), [Mastra: database templates](https://mastra.ai/docs)

## Burn-in result

The local example passes. SQL generation, read-only policy, database execution,
and typed formatting are separate Flow steps. Unsafe SQL fails before the
database adapter is called.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_10_safe_sql_assistant/safe_sql_assistant.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_10_safe_sql_assistant/safe_sql_assistant_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
