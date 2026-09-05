> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Round-Robin Local Router

- **Status:** archived research
- **Complexity level:** 1 - Foundation
- **Feature group:** basic
- **Test class:** local deterministic

## Profile

- **Purpose:** Show deterministic work selection without child processes.
- **User story:** As a scheduler, I assign each item to the next logical worker ID.
- **Trigger or input:** `router.assign` Signal with a work item.
- **Agent state:** Ordered worker IDs, next index, and assignment records.
- **Actions or Flow:** One Action selects the next worker and advances the index.
- **External interactions:** None.
- **Runtime Directives or capabilities:** None at this level. A later example emits work to real child Actors.
- **Expected result:** Assignments rotate in stable order and wrap at the end.
- **Failure cases:** No workers or invalid index.
- **Jido features under pressure:** Deterministic selection, collection state, and a later migration to child Actors.
- **Source framework and links:** [AutoGen: teams tutorial](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html), and [Basic SDK suite](../../../../test/examples/01_basic/README.md)

## Current scope

This is an archived research profile from the original catalog. Its source
folder and repeated domain tests were removed. It is not a current SDK
acceptance claim. See the [five Basic fixtures](../../../../test/examples/01_basic/README.md)
and [current results](../../basic-results.md) for the implemented obligations.
