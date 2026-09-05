> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Session-Replayed Task Board

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_11_session_replayed_task_board`
- **Status:** implemented
- **Complexity level:** 3 - Session state
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Keep a visible task dependency graph that can be rebuilt from committed session entries.
- **User story:** As a user, I can restart an Agent or compact its model context without losing its task plan.
- **Trigger or input:** Signals add, start, complete, block, unblock, or remove tasks.
- **Agent state:** Current task projection, dependency edges, active task ID, completed count, and the Thread entries used for replay.
- **Actions or Flow:** Each task Signal selects one Action. The Action validates the dependency graph, appends one complete post-change snapshot entry, and returns one next state.
- **External interactions:** None. A local renderer process can observe state but does not own it.
- **Runtime Directives or capabilities:** None for task mutation. Restart uses normal Actor persistence and restoration.
- **Expected result:** Task state stays isolated per Agent, dependency cycles are rejected, restart rebuilds the same projection, and model-context compaction does not change the board.
- **Failure cases:** Duplicate ID, missing dependency, self-dependency, dependency cycle, invalid status change, corrupted replay entry, or stale concurrent update.
- **Jido features under pressure:** Thread entries, Actor persistence, replay, projection validation, session isolation, and separation of domain state from UI.
- **Source framework and links:** [Pi todo package](https://pi.dev/packages/@juicesharp/rpiv-todo) and [Pi stateful extension examples](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions)


## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_11_session_replayed_task_board/session_replayed_task_board.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_11_session_replayed_task_board/session_replayed_task_board_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
