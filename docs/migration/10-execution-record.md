# Core execution record

Start: `f67eeb1e54709be13bb25d13b5d81f00909d8b41` on `v3-spike`.
Source: `jido_v3@bf6c9fbec569cb6438b6a1629a2768058d439d1f`.
The two donor checkouts remain read-only. All transfers use Git objects at this
source commit. No donor history is merged into core.

## M01 — inputs and acceptance records

The immutable input audit now permits core changes. A separate target audit
checks the stage, destination collisions, hashes and declared deviations.
The file register assigns all 278 old core files before the cutover. It records
old test names and public functions for the final compatibility audit.

The copied check runner and ExUnit formatter retain commands, runtime, seed,
individual results and logs. New records also contain per-file code hashes and
the staged Git tree. This identifies tested content before its local commit.

The unchanged V2 baseline had one stale observation assertion: it expected a
raw exception and stacktrace from public telemetry. Core already projects a
safe error map and removes the stacktrace. The corrected test requires that
exact map and the absence of the stacktrace. Its six observation checks will
remain in core after the API port. Both failed runs remain in the evidence.

| Check | Result | Evidence |
| --- | --- | --- |
| Immutable source and manifest audit | Pass; 667 source hashes, 52 fixtures, 10 applications | `evidence/plan-checks.json` |
| Target audit M01 | Pass; formatter hash checked | `python3 docs/migration/verify_target.py M01` |
| Compilation with warnings as errors | Pass | `evidence/core/m01-compile.json` |
| Initial full V2 suite | 2,298 pass, 1 fail | `evidence/core/m01-test.json` |
| First assertion correction | 2,298 pass, 1 fail; stale stacktrace assertion exposed | `evidence/core/m01-test-fixed.json` |
| Full V2 suite after correction | 2,299 pass, 0 failures, 0 skips; 43.518 seconds | `evidence/core/m01-test-final.json` |

Runtime: Elixir 1.20.3 / OTP 29.0.5. Exact commands are in the linked command
records. These V2 results are not V3 acceptance.

## M02 — runtime replacement and Basic examples

The complete Agent, AgentServer, Plugin and persistence unit uses the pinned
source. This includes the prepared remote, hibernation, scheduler and Registry
fixes. Topology remains assigned to M10. The cutover removes 213 recorded V2
paths. The old observation example remains, with V3 routes, complete candidate
state and the same six behavior checks.

The checkpoint-identity fixture and its shared byte store arrive in M02 because
the naming tests need them. Support that needs later examples arrives with those
examples. These stage changes are recorded in `transfer-plan.json`.

Package files include core modules and the existing usage rules. They exclude
`lib/examples`, which uses optional model clients. Local example paths do not
change. The dependency set uses Action beta.6, Signal beta.2 and SchedEx 1.2.1.
`mix deps.get` passed; its log records a Mint advisory. The main-branch fix is
assigned to M12, before beta QA.

- `m02-compile-final.json`: compilation with warnings as errors passed.
- `m02-test.json`: 611 tests passed, zero failures or skips, 31.818 seconds
  including test dependency compilation. ExUnit took 5.4 seconds.
- `m02-test.results.stage.json`: all 605 introduced source tests are present.
  Five Basic fixtures pass 16 checks; shared authoring adds six checks.
  The retained observation example adds six checks to the source total.
- The input audit passes. The target audit checks 178 transferred paths.
  No current Actor runtime or temporary alias was introduced.

All command records use Elixir 1.20.3 / OTP 29.0.5. The per-file hashes identify
runtime and test content. Script-only additions after a test run do not change
that tested runtime content.

## M03 — persistence boundaries

The cumulative suite passes 654 tests with zero failures or skips in 8.708
seconds. This includes all ten identity, portability and uncertain-write probes,
plus ETS, File, Redis adapter and direct/live persistence tests. The assertions
and fixtures match the pinned source. Unknown writes and raised callbacks stop
the writer; old envelope formats are rejected. Mock Redis checks do not prove
real Redis failover. Compilation with warnings as errors passes.

Commands and test selections: `evidence/core/m03-compile.json`,
`evidence/core/m03-test.json`, and `evidence/core/m03-test.results.stage.json`.

## M04 — remote admission and lifecycle

The cumulative suite passes 655 tests with no failures or skips in 16.151
seconds. The peer test starts real nodes 6.1 seconds apart. Both call directions,
call/request deadlines, infinite waits and live/dead remote PIDs pass.

Three more seeds each pass all 13 remote API, instance and startup checks. These
include immediate hibernate/thaw, current-state restart and stale Registry checks.
The tests preserve their barriers and process cleanup. Compilation passes with
warnings as errors. RemoteCounter and KeepState arrive early as source dependencies;
the complete Multi-agent group remains assigned to M08.

See `evidence/core/m04-compile.json`, `m04-test.json`,
`m04-test.results.stage.json` and `m04-repeat-1.json` through
`m04-repeat-3.json` in the same evidence folder. A partition still does not prove
remote death or cluster-exclusive ownership.

## M05

All nine Workflow fixtures pass their 35 checks. They keep actual Flow dependencies, parallel execution, ordered results, loop bounds, continuation and approval Turns. Source and test bytes match the prepared source.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 690}]` in 17.177 seconds, with normal concurrency.
See `evidence/core/m05-compile.json`, `evidence/core/m05-test.json`
and `evidence/core/m05-test.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.

## M06

All ten LLM fixtures pass 66 checks. Tests use deterministic adapters. They preserve tool validation and ordering, history, repair limits, child delegation and the recursive corpus oracle. The stress runner is copied for its separate M13 scale check.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 756}]` in 22.487 seconds, with normal concurrency.
See `evidence/core/m06-compile.json`, `evidence/core/m06-test.json`
and `evidence/core/m06-test.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.

## M07

All 13 Runtime fixtures pass 94 checks, including the supporting core files outside the catalog folders. The prepared assertions prove commit-before-ack delivery, replay, saved job attempts, early timer handling, durable occurrence identity and remote trace/VM recovery. All transferred source and test bytes remain unchanged.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 850}]` in 37.714 seconds, with normal concurrency.
See `evidence/core/m07-compile.json`, `evidence/core/m07-test.json`
and `evidence/core/m07-test.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.

## M08

All six Multi-agent fixtures pass 38 checks. Real child startup, restart, bounded workers, hierarchy shutdown, remote placement, disconnect and explicit replacement after reconnect remain unchanged. These checks do not establish cluster-exclusive ownership.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 888}]` in 60.263 seconds, with normal concurrency.
See `evidence/core/m08-compile.json`, `evidence/core/m08-test.json`
and `evidence/core/m08-test.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.

## M09

All four Factory systems pass their 48 direct checks. Shared streaming adds nine checks across seven test files. Tests use real local HTTP/SSE adapters, the real worker timing barrier and the nine-worker Flow graph. No provider key or paid session is used.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 945}]` in 152.15 seconds, with normal concurrency.
See `evidence/core/m09-compile.json`, `evidence/core/m09-test.json`
and `evidence/core/m09-test.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.

## M10

Transferred Topology and all five catalog fixtures, including the 1,000-worker test. All 52 Topology tests passed in the first run. That run failed one existing directive failure-notification test. The next full run passed all 997 tests; ten focused seeds passed all 20 selected tests. The one-second assertion and all outcome checks remain intact. Added process diagnostics for a repeated failure. The cause of the first failure is not known; retain it as an open investigation for the full seed campaign. See m10-test.json and m10-directive-0.json through m10-directive-9.json.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 997}]` in 161.311 seconds, with normal concurrency.
See `evidence/core/m10-compile.json`, `evidence/core/m10-diagnostic-full.json`
and `evidence/core/m10-diagnostic-full.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.

## M11

All ten application scenarios pass, including saved group recovery, newer attempts and stale-result rejection. The complete prepared set now passes in core. DIST-03 is the only excluded test; its original assertion and stated limit remain intact. All other research and real-node tests ran.

Compilation with warnings as errors passes. The cumulative suite result is
`[{'passed': 1011, 'excluded': 1}]` in 161.877 seconds, with normal concurrency.
See `evidence/core/m11-compile.json`, `evidence/core/m11-test.json`
and `evidence/core/m11-test.results.stage.json` for commands, source coverage,
per-test results and runtime. Source changes require a reason in the transfer ledger.
