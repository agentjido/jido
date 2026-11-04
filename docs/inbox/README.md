---
title: Documentation inbox
status: current
last-reviewed: 2026-11-04
---

# Documentation inbox

This directory is the queue for material that still needs review. Content in
this queue is not proof of current behavior or accepted intent.

## Intake log

`new` means that the content needs review. `placed` means that setup kept the
item at a required path. It does not mean that setup verified the content.

| Original path | Actual location | Intake date | Status | Exception or result |
| --- | --- | --- | --- | --- |
| `docs/plans/2026-11-03-1512-consolidated-quality-backpressure-plan.md` | `docs/inbox/docs/plans/2026-11-03-1512-consolidated-quality-backpressure-plan.md` | 2026-11-04 | `new` | Moved with no content change; no current path consumer was found. |
| `README.md` | `README.md` | 2026-11-04 | `placed` | Required project entry point. |
| `AGENTS.md` | `AGENTS.md` | 2026-11-04 | `placed` | Required project instructions. |
| `docs/adr/*.md` (5 files) | `docs/adr/*.md` | 2026-11-04 | `placed` | Project instructions require architecture decisions and their index at this path. |
| `docs/plans/2026-11-04-1255-test-flow-authoring-suite-plan.md` | Same as original path | 2026-11-04 | `placed` | The test tree refactor plan links to this plan. |
| `docs/plans/2026-11-04-1314-refactor-jido-test-tree-plan.md` | Same as original path | 2026-11-04 | `placed` | `test/quality/test_tree_refactor.yml` requires this path. |
| `guides/dynamic-flows.md` | `guides/dynamic-flows.md` | 2026-11-04 | `placed` | A public module link and an executable guide test require this path. |
| `examples/**/README.md` (136 files) | Same as original paths | 2026-11-04 | `placed` | These files are part of the supported example tree and its relative link graph. |

## Next action

Review one `new` item. Check its claims against current code, tests,
configuration, and accepted decisions. Then place it in a current category or
archive it with its provenance.
