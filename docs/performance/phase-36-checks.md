# Checks after idea Round 36

The cycle has 36 completed idea decisions: nine accepted fixes, six measured
rejections, and 21 source or contract rejections. Fourteen ideas remain,
including the final 50-pair combined run. This is a progress checkpoint.

Round 14 removed a second keyword-list scan. Five fresh-VM pairs showed about
17% less median time for append batches and 35% to 50% less time for replacement
with a non-keyword list. Sampled process memory and copied result sizes stayed
the same. [The round report](round-14-keyword.md) gives all cases and controls.

Round 17 tested two ways to update replacement budget fields. Both were
removed. One slowed transitions; the other had no qualifying time or copied
memory gain. [The report](round-17-replacement.md) retains both trial patches.

## Complete checks

Runtime commit: `598626a4`.

- Core, integration, and flaky selection: **892 passed**, one existing DIST-03
  exclusion. Core coverage: **83.5%**, above the 80% gate.
- Coverage excludes examples, test fixtures, and benchmark helpers.
- Separate example selection: **272 passed, 11 failed**. Failure names and
  modules exactly match the prior Round 34 run. No failure was added or removed.
- Format, compile with warnings as errors, strict warning lint, and Dialyzer
  passed through `mix quality`.
- Documentation with warnings as errors and package construction passed.
- All **215 scale cases** passed result, copied-term, and cleanup checks on
  Elixir 1.20.3 / OTP 29. No owned helper remained in any resource sample.
- All **97 smoke cases** passed on Elixir 1.18.5 / OTP 27.3.4.12. This was a
  compatibility run, not paired timing evidence. Floor builds use the isolated
  Hex archive and build directory described in the prior check report.

Commands follow [the prior complete checks](phase-34-checks.md), with output
paths changed from `phase-34` to `phase-36`. The coverage scope and threshold
are unchanged. The exact commands and source hashes remain in local reports.

Local logs: `/tmp/jido-phase-36-{coverage,examples,quality,docs,package,floor,scale}.log`.
Reports: `bench/results/phase-36-scale` and `bench/results/phase-36-floor-smoke`.
The benchmark profiles now contain 97 smoke, 174 short, and 215 scale cases.
