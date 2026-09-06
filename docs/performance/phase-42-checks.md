# Checks after 42 idea decisions

The cycle has 42 completed decisions: eleven accepted fixes, eight measured
rejections, and 23 source or contract rejections. Eight rounds remain, including
the final 50-pair combined run.

[Round 48](round-48-scheduler-capture.md) removes the complete runtime map from
the scheduler delivery task function. Five pairs showed 88% less time for a
large map and 78% less for a large list, with lower sampled process peaks.
Separate actual-function copy probes confirmed the cause. Round 29 rejected
unconditional target validation caching because a later descriptor can fail.

## Checks

Runtime commit: `16531024`. Codec fixture commit: `0ae1e948`.

- Core, integration, and flaky selection: **894 passed**, one existing DIST-03
  exclusion. Core coverage: **83.5%**. Examples, test fixtures, and benchmark
  helpers remain outside the 80% gate.
- Separate example selection: **272 passed, 11 failed**. The failure names and
  modules exactly match phase 40.
- Format, warnings-as-errors compile, strict warning lint, Dialyzer,
  documentation, and package checks passed.
- All **253 scale cases** passed result, copied-term, and process cleanup checks
  on Elixir 1.20.3 / OTP 29. No owned helper remained.
- All **132 smoke cases** passed on Elixir 1.18.5 / OTP 27.3.4.12.
- The scheduler and benchmark selection passed **28 tests**. The added codec
  boundary and fixture selection passed **35 tests** before the Round 34 trial.

Core and quality logs use `/tmp/jido-phase-41-{coverage,examples,quality,docs,package}.log`.
The full benchmark logs use `/tmp/jido-phase-42-{scale,floor}.log`.
Reports are `bench/results/phase-42-scale` and `bench/results/phase-42-floor`.
The floor run uses the isolated archive and build path from prior checks.
Profiles contain 132 smoke, 212 short, and 253 scale cases.

An optional floor baseline function-copy probe could not build its separate
checkout because a compatible rebar3 was absent. This does not affect the
completed floor smoke run or the five paired OTP 29 measurements. The floor
candidate-only function probe confirms that the runtime map is not captured;
it does not provide a floor before/after comparison.
