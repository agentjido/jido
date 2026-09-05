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
