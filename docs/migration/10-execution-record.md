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
