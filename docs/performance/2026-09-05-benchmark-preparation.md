# Core benchmark preparation: 2026-09-05

Base runtime: `b770efa7` on `v3-spike`.
Benchmark and coverage revision: `f710ebe2d5b89884ce47b2364bbf35f1fb3b2f93`.
Elixir 1.20.3; OTP 29; Apple M1 Max; two online schedulers.
Dependency lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Tool SHA-256: `cd2b7783b9026cfd7f474e7fcf47b1411169bb3bbebc3a86e61d3b27780fe9d5`.

## Checks

- Core coverage: **83.4%**. Core test selection: **884 passed, one excluded**.
  The existing DIST-03 exclusion remains unchanged. Example source, test source,
  and benchmark helpers are outside the 80% core coverage gate.
- Complete behavior selection, including examples: **1156 passed, 11 failed,
  one excluded**. All 11 failures also occurred before the benchmark work.
  The failures concern research examples for input runtime reconstruction,
  route selection (two), Plugin isolation (two), stable references, durable
  deletion, state migration, definition revision, Turn upgrade, and topology
  upgrade. No test was removed or hidden.
- Six benchmark contract tests passed. These check all smoke results, process
  cleanup after failure, repeated resource samples, transfer bounds, and report
  compatibility checks.
- Smoke: **51 cases**. Short: **122 cases**. Scale: **159 cases**. All result,
  cleanup, and term transfer checks passed.
- Smoke also passed on **Elixir 1.18.5 / OTP 27.3.4.12**. This was a compatibility
  run, not a performance comparison with OTP 29.
- Format, compile with warnings as errors, strict warning lint, Dialyzer, docs
  with warnings as errors, and Hex package build passed.

Core coverage command:

```sh
ERL_FLAGS='+S 2:2' mix test --cover test/jido test/jido_test test/integration --include integration --include flaky --seed 0
```

## Baseline sample

These are local measurements, not speedup claims. Process bytes are sampled
maxima from separate calls that include setup and checks. Compare revisions on
the same idle host with the same tool and settings.

| Case | Median microseconds | Observed process bytes |
| --- | ---: | ---: |
| agent/cmd/routes_1/small | 70.92 | 16408 |
| agent/cmd/routes_16/small | 290.38 | 40120 |
| agent/cmd/routes_1/large_map | 171.88 | 518000 |
| agent/cmd/routes_1/large_list | 135.79 | 693376 |
| server/call/small | 199.08 | 96488 |
| server/call/large_map | 658.54 | 883624 |
| server/call/large_list | 489.12 | 1608632 |
| thread/normalize/1000 | 130.12 | 743584 |
| audit/update/1000/1 | 6.75 | 372208 |
| observe/span | 1.00 | 2696 |

## Local evidence

Raw JSON, Markdown reports, and paired command logs remain under the ignored
`bench/results/` directory. The valid baseline directories are `baseline-short`
and `baseline-scale-clean`. The valid unchanged-code control is
`control-pairs-clean`.

The earlier `baseline-scale` and `control-pairs` runs may overlap. They are marked
invalid in `bench/results/contaminated.json` and are not used for acceptance.

See the [50-round plan](../plans/2026-09-05-core-performance.md) and
[benchmark guide](../../guides/benchmarks.md) for the next steps. A repeated
measurement pair is not a separate optimization idea.
