> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Task List

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show list state, stable item IDs, and idempotent updates.
- **User story:** As a user, I add, complete, reopen, and remove tasks.
- **Trigger or input:** Task lifecycle Signals with a task ID.
- **Agent state:** Ordered task records and the next local ID.
- **Actions or Flow:** One Action applies one lifecycle change and returns the full task list.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None.
- **Expected result:** The requested item changes once and list order stays stable.
- **Failure cases:** Missing item, duplicate ID, invalid title, or forbidden transition.
- **Jido features under pressure:** Collection schemas, idempotency, deterministic ordering, and state size.
- **Source framework and links:** [Sagents: TodoList middleware in current API](https://sagents.hexdocs.pm/api-reference.html), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
