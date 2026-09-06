# Core benchmark preparation: 2026-09-05

Base runtime: `b770efa7` on `v3-spike`.
Measured candidate revision: `beaefe2bf33a1f785873ff5d00e48800b6ceb93a`.
The candidate includes the accepted Round 07 Audit change. Round 01 was rejected.
Elixir 1.20.3; OTP 29; Apple M1 Max; two online schedulers.
Dependency lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Tool SHA-256: `1e17fe878a82107a2dbe9f4209e9aa2464de525238297a885491538347c0b306`.

## Checks

- Core coverage: **83.4%**. Core test selection: **888 passed, one excluded**.
  The existing DIST-03 exclusion remains unchanged. Example source, test source,
  and benchmark helpers are outside the 80% core coverage gate.
- Complete behavior selection, including examples: **1160 passed, 11 failed,
  one excluded**. All 11 failures also occurred before the benchmark work.
  The failures concern research examples for input runtime reconstruction,
  route selection (two), Plugin isolation (two), stable references, durable
  deletion, state migration, definition revision, Turn upgrade, and topology
  upgrade. No test was removed or hidden.
- Seven benchmark contract tests passed. These check all smoke results, process
  cleanup after failure and untraced calls, repeated resource samples, transfer bounds, and report
  compatibility checks.
- Smoke: **53 cases**. Short: **124 cases**. Scale: **161 cases**. All result,
  cleanup, and term transfer checks passed.
- Smoke also passed on **Elixir 1.18.5 / OTP 27.3.4.12**. This was a compatibility
  run, not a performance comparison with OTP 29.
- Format, compile with warnings as errors, strict warning lint, Dialyzer, docs
  with warnings as errors, and Hex package build passed.

Core coverage command:

```sh
ERL_FLAGS='+S 2:2' mix test --cover test/jido test/jido_test test/examples/08_applications --include integration --include flaky --seed 0
```

## Candidate sample

These are local measurements, not speedup claims. Process bytes are sampled
maxima from separate calls that include setup and checks. Compare revisions on
the same idle host with the same tool and settings.

| Case | Median microseconds | Observed process bytes |
| --- | ---: | ---: |
| agent/cmd/routes_1/small | 66.00 | 16408 |
| agent/cmd/routes_16/small | 300.25 | 40120 |
| agent/cmd/routes_1/large_map | 149.58 | 518000 |
| agent/cmd/routes_1/large_list | 116.21 | 693376 |
| server/call/small | 167.04 | 99496 |
| server/call/large_map | 647.71 | 883624 |
| server/call/large_list | 513.67 | 1608632 |
| thread/normalize/1000 | 90.71 | 743584 |
| audit/update/1000/1 | 6.12 | 372208 |
| observe/span | 0.62 | 2696 |

## Local evidence

Raw JSON, Markdown reports, and paired command logs remain under the ignored
`bench/results/` directory. Current schema 2 candidate reports are `final-short`
and `final-scale`. The runtime-floor compatibility report is `final-floor-smoke`.
Its timings are not used for performance claims.

`round-07-final` contains five fresh-VM pairs with the current tool. See the
[accepted Audit result](round-07-audit-record.md) and the
[rejected Thread result](round-01-thread-normalization.md). The earlier
`baseline-short`, `baseline-scale-clean`, and `control-pairs-clean` reports use
schema 1. They are historical records and must not be compared with schema 2.

The earlier `baseline-scale` and `control-pairs` runs may overlap. They are marked
invalid in `bench/results/contaminated.json` and are not used for acceptance.

See the [50-round plan](../plans/2026-09-05-core-performance.md) and
[benchmark guide](../../guides/benchmarks.md) for the next steps. A repeated
measurement pair is not a separate optimization idea.
