# Round 45 status at transfer

The user requested that the current work be committed and merged into the main
`proj_jido_core/jido` checkout. The cycle is paused at 44 of 50 recorded decisions:
12 accepted fixes, nine measured rejections, and 23 source or contract rejections.
Rounds 24, 33, 42, 45, 47, and 50 remain open. The final 50-pair run is not complete.

## Current code

The main checkout receives the current Round 45 candidate, `fedbdf10`, as work
in progress. It reuses metadata and the tracer already resolved at synchronous
legacy span start. Public asynchronous spans and the scoped tracer path keep
their existing implementation. This candidate is not an accepted optimization.

Commit `9647cf87` adds 12 Observe benchmark cases and a test for correlation
created inside a span. The suite now has 144 smoke, 224 short, and 265 scale cases.
Commit `6fcfc2f4` fixes a test cleanup race by using supervised counters.

The [saved patch](trials/round-45-span-start.patch) records the earlier, broader
trial `9ccba485` against `6fcfc2f4`. That trial also changed asynchronous span
startup and start-event emission. It was replaced by the narrower current trial;
the patch is a record, not a change to apply to the current candidate.

## Evidence so far

Baseline: `6fcfc2f4`. Candidate: `fedbdf10`.
Environment: Elixir 1.20.3, OTP 29.0.5, Apple M1 Max, two schedulers, Mix dev.
Measurements use five fresh-VM pairs in alternating order.

After a forced full project compile in both checkouts, the eight Noop and
legacy batch cases have median time ratios from 0.731 to 0.769. At least four
of five pairs improve in each case. Scoped tracer time ratios are 0.983 to 1.012.
These are preliminary results. Some Observe sampled peaks still increase:

| Case | Candidate/baseline sampled peak |
| --- | ---: |
| Noop, no correlation, empty metadata | 2.914 |
| Legacy, correlation, empty metadata | 1.473 |
| Legacy, correlation, 1000 metadata fields | 1.306 |

Before the full rebuild, several Server cases showed large peak increases,
including paths that do not use the changed function. After the full rebuild,
no Server median peak ratio exceeded 1.018. This result requires investigation
of build effects. It does not establish the cause of the earlier differences.

`bench/repeat.py` still uses `mix compile --warnings-as-errors` without `--force`.
The full rebuild was manual. Before further decisions, make full compilation
part of the comparison procedure and run an unchanged control. Recheck the
memory evidence used to reject rounds 20, 22, and 28 if build effects apply.
Their recorded decisions remain unchanged until that work is complete.

The [heap allocation probe](probes/round-45-heap.exs) completed one candidate
preflight with 11 cases and ten checked invocations per case. Paired allocation
checks are not complete. This probe measures profiled heap allocation with
setup and cleanup. It does not measure peak live memory or off-heap allocation.

Local raw reports remain in the benchmark worktree under `bench/results/`:

- `round-45` and `round-45-server`: the earlier broad trial.
- `round-45-control`: unchanged control.
- `round-45-sync` and `round-45-sync-server`: current trial before full rebuild.
- `round-45-sync-forced` and `round-45-sync-server-forced`: after full rebuild.
- `round-45-heap-preflight.json`: one candidate allocation probe.

These ignored reports are not part of the merge. Keep the benchmark worktree
until the cycle is complete or the raw evidence is moved to a durable archive.

## Checks and remaining work

The current candidate passed 193 focused Observe and benchmark tests. Both
checkouts passed a forced full compile with warnings treated as errors. The
allocation preflight finished successfully. Logs are under
`/tmp/jido-round-45-{sync-tests,force-base,force-candidate,heap-preflight}.log`.

Before transfer, the current candidate passed 899 core, integration, and flaky
tests with one existing DIST-03 exclusion. Core coverage is 83.5%, above the 80%
gate. Format, compile with warnings as errors, strict warning lint, Dialyzer,
documentation, and package checks passed. Commands used `ERL_FLAGS='+S 2:2'`:

```sh
mix coveralls test/jido test/jido_test test/integration --include integration --include flaky --seed 0
mix format --check-formatted docs/performance/probes/round-45-heap.exs
mix quality
mix docs --no-open
mix hex.build
```

Logs: `/tmp/jido-main-handoff-{core,quality,docs,package}.log`. This transfer check
did not repeat the example suite or the minimum-runtime checks.

The previous [full checks](phase-43-checks.md) passed 898 core tests with 83.5%
core coverage. The separate example run had 272 passes and 11 existing failures.
Examples, test fixtures, and benchmark helpers remain outside the coverage gate.
The current candidate still needs a performance decision, checks on the minimum
runtime, and the final combined measurements. Do not describe Round 45 as an
accepted fix or the 50-round cycle as complete.
