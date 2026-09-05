# Prepared donor record

Verified on 2026-09-05. The preparation task is complete. Core transfer has not
started. Use tested source `bf6c9fbec569cb6438b6a1629a2768058d439d1f`.
Report commit `741058d128928d05bdee109f3c6a0425eb82db89` is its child and
changes only `docs/migration-preparation`.

The local branch is `prep/agent-migration`. The worktree is
`/Users/mhostetler/.codex/worktrees/0d9b/jido_v3` and is clean.
The original donor remains clean at `ba00fcf` on `main`. No source was pushed,
merged, published, or transferred into core.

## Completed source commits

| Commit | Completed work | Core handling |
| --- | --- | --- |
| `4a7a4b2` | Check restored identity and recursive portable data; stop uncertain writers | Transfer implementation in M02; prove complete boundaries in M03 |
| `a749bb7` | Compare remote admission in the caller clock domain; bound remote liveness; wait for hibernation termination | Transfer in M02; retain real-node and lifecycle checks in M04 |
| `33c1420` | Use instance-scoped group Buses; restore Fixed Group history; retry Elastic work with attempt identity | Transfer complete prepared application fixtures in M11 |
| `8107581` | Wait for the scheduled instant before the default clock callback delivers and returns | Transfer Scheduler code in M02; complete scheduling checks in M07 |
| `db4c294` | Record exact commands and individual test results | Review and adapt test tooling in M01 |
| `3a48d7d` | Load application modules and packaged model metadata before concurrent tests | Preserve required test startup order; do not serialize the suite |
| `2f75b88` | Filter stale Registry PIDs from live lookup, list, and count | Transfer with M02 and its controlled regression |
| `efc5b0d` | Remove absent usage-rules.md from the package list | Reconcile against core files in M12; do not delete an existing core guide by inference |
| `08117d1` | Change framework names to Agent and AgentServer | Transfer prepared content without another rename |
| `7e18634` | Mark persistence probes fixed; retain research limits | Previous tested source |
| `73b21d5` | Store the first final report and evidence | Preserve as historical evidence |
| `17f3d85` | Skip only DIST-03 by user request | Keep the exact manifest exception |
| `bf6c9fb` | Hold the real worker during Factory scheduler assertions; handle the skip tag in reporting | Current tested source |
| `741058d` | Record the follow-up test evidence | Current report commit |

The [exact path map](evidence/prepared/name-path-map.json) records 455 files
changed by naming and 97 path changes. Its base is `efc5b0d`, the final Actor
implementation. The core manifest also retains original `ba00fcf` paths.

## Selected behavior

- A matching outer checkpoint cannot conceal a different restored Agent ID
  or module. Recursive load validation rejects nonportable values.
- Unknown write results stop the writer before another Action can execute.
  Shutdown does not save stale state. Raised or malformed callbacks are uncertain.
  Other adapter errors must confirm that the proposed write was not stored.
- Remote admission queries the caller's monotonic clock with a one-second
  bound. Unavailable clock evidence rejects admission. Infinite budgets need
  no clock query. A caller timeout still does not undo active external work.
- Remote `alive?/1` returns false when liveness cannot be confirmed. During
  a partition, false does not prove process death.
- Hibernation returns success after process termination. Immediate thaw can
  then create a replacement.
- Fixed Group restores its full saved state and exact task history. Elastic
  Group retries saved input with a newer attempt and rejects stale completion.
- The default Scheduler clock waits for the intended slot. Repeated delivery
  of one logical occurrence retains its ID. Custom clocks keep their own semantics.

## Formats and design

The prepared format uses `jido:agent:v1:`, `kind: :agent`, `agent_module`, and
`agent_id`. Authoring JSON uses `jido.agent`; Topology uses `agents`.
Old Actor keys are not read, and an old envelope moved to a new key is rejected.
There is no automatic Actor or core V2 storage conversion. Do not rewrite opaque
checkpoint bytes in place. See the copied [serialization contract](evidence/prepared/serialized-formats.md).

Builder, Codec, child ownership, and Topology remain implemented. The Ref facade,
new Plugin pipeline, and new persistence architecture remain proposals. Historic
Actor names remain only where they describe history or test old-format rejection.

## User-approved test scope

Commit `17f3d85` skips only DIST-03 at the user's request. Commit `bf6c9fb`
corrects a Factory test timing race by holding its real worker during the
busy-poll assertion. The focused test passes five runs. The final full suite now
passes 1005 tests with zero failures and one skip. The companion authority test
remains active. ExUnit reports the skip as excluded because its configuration
excludes the skip tag. The manifest allows only the exact skipped file and test name.
See the [current run](evidence/prepared/scoped-final-full-seed-0.json).

The records below describe earlier preparation runs. No production code changed
for this follow-up. Core transfer, burn-in, and final beta QA remain pending.

## Previous verified evidence

The local verification checked committed source bytes, copied evidence bytes,
per-test results, manifest selections, and both preserved checkouts. Two full
concurrent commands and a focused repeat command ran after the skip. The first
full run exposed the Factory timing race; all evidence is retained. Exact commands,
revisions, runtime, exit status, and individual results are retained here.

- Concurrent suite: 1005 passed, one DIST-03 failure. Its code revision is
  `08117d1`; the changes to `7e18634` are status documents only.
- Serial and concurrent coverage suites at `7e18634`: 1005 passed, one DIST-03
  failure each. There are no skipped or excluded tests in these result records.
- Catalog and shared checks: 317 passed. All 52 fixtures have nonempty checks.
  All 10 application scenarios passed 13 tests. Topology supporting tests passed 47.
- Required repeat: 42 tests passed in each of five runs.
- Coverage: 83.0%, above the unchanged 80% threshold. AgentServer is 78.3%;
  child placement and spawn Registry remain low at 13.7% and 19.0%.
- Format, compilation, Dialyzer, docs, and local package build passed. Credo
  ran zero checks on 372 files. A substantive lint review remains required.

See [validation](05-validation.md), the [copied command records](evidence/prepared-summary.json),
and the [original preparation report](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/migration-preparation/README.md).

## Remaining limits

DIST-03 still allows concurrent owners of one logical identity on two nodes.
CAS prevents stale storage writes; it does not stop both owners from doing
external work. The user approved deferring this assertion with an explicit skip.
The implementation limit remains; do not count the skipped test as passing.

The declared Elixir 1.18/OTP 27 floor, 10-seed campaign, 30-minute workload,
real multi-host partition recovery, real Redis failover, downstream package
compatibility, and clean package consumer remain unverified. Tests used
Elixir 1.20.3/OTP 29.0.5 and deterministic model adapters or local HTTP/SSE.
No paid provider session ran.

Earlier concurrent timeout failures are retained in the donor report. The
Directive timeout did not recur in 31 focused runs or the final full runs;
this does not prove all timing sensitivity is absent. Core must run its own
complete acceptance and burn-in checks.
