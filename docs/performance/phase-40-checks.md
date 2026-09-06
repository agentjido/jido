# Checks after 40 idea decisions

The cycle has 40 completed decisions: ten accepted fixes, eight measured
rejections, and 22 source or contract rejections. Ten ideas remain, including
the final 50-pair combined run. Round 48 is open for scheduler task capture.

[Round 36](round-36-ets.md) reduced default ETS table-name work. Default
operation batches improved by 30% to 66%. The report records a 3,016-byte
sampled peak increase for one retained-result batch and the follow-up write
loop checks. [Round 22](round-22-schema.md) was removed after wider regressions.

## Complete checks

Runtime commit: `763e351e`. Benchmark fixture commit: `f71f842c`.

- Core, integration, and flaky selection: **893 passed**, one existing DIST-03
  exclusion. Core coverage: **83.5%**, above the 80% gate.
- Coverage excludes examples, test fixtures, and benchmark helpers.
- Separate example selection: **272 passed, 11 failed**. Failure names and
  modules exactly match the prior phase-36 run.
- Format, warnings-as-errors compile, strict warning lint, and Dialyzer passed
  through `mix quality`. Documentation with warnings as errors and package
  construction passed.
- All **237 scale cases** passed result, copied-term, and cleanup checks on
  Elixir 1.20.3 / OTP 29. No owned helper remained.
- All **116 smoke cases** passed on Elixir 1.18.5 / OTP 27.3.4.12, including the
  new scheduler task fixture. This was a compatibility check, not paired time
  evidence. Floor builds use the isolated Hex archive and build directory.
- The new scheduler fixtures and scheduler contract selection passed **27 tests**.

Commands follow [the prior complete checks](phase-36-checks.md). The coverage
command explicitly sets `MIX_ENV=test` for `mix coveralls.json`. The scope and
80% threshold are unchanged. Raw reports record source and tool hashes.

Local logs: `/tmp/jido-phase-40-{coverage,examples,quality,docs,package,scale}.log`,
`/tmp/jido-phase-40-scheduler-tests.log`, and
`/tmp/jido-phase-40-floor-scheduler.log`.
Reports: `bench/results/phase-40-scale` and `bench/results/phase-40-floor-scheduler`.
Profiles now contain 116 smoke, 196 short, and 237 scale cases.
