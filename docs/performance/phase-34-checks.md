# Checks after idea Round 34

The cycle has 34 completed idea decisions: eight accepted fixes, five measured
rejections, and 21 source or contract rejections. Sixteen ideas remain,
including the final 50-pair combined run. This is a progress checkpoint.

The new accepted fixes in this batch are:

| Round | Target | Measured result |
| ---: | --- | --- |
| 05 | Single-kind Thread filtering | 39% to 49% less median time at 100 to 10,000 entries; sampled memory unchanged |
| 16 | State budget checks | Small-state 100-check batches use 21% to 24% less median time; sampled memory unchanged |
| 18 | Reserved command context keys | Prepare uses 36% less median time at 1,000 keys and 88% less at 10,000 keys; sampled memory unchanged |
| 31 | Generated Codec encoding | Neutral definitions use 29% to 43% less median time; larger generated cases have lower sampled process peaks |

Each fix has five fresh-VM pairs and an unchanged-code control. The individual
reports state case limits, outliers, resource results, and source hashes.
The Codec report also records a higher peak in one setup/operation workload
and its fixed-input follow-up. These are workload results, not an overall
Jido throughput percentage.

## Complete checks

Runtime commit: `3e58775f`.

- Core, integration, and flaky selection: **892 passed**, one existing DIST-03
  exclusion. Core coverage: **83.5%**, above the 80% gate.
- Coverage excludes `lib/examples/`, test fixtures, and benchmark helpers.
- Separate example selection: **272 passed, 11 failed**. Failure names and test
  modules exactly match the prior Round 39 run. No example failure was added
  or removed. These known research-example failures remain unresolved.
- Format, compile with warnings as errors, strict warning lint, and Dialyzer
  passed through `mix quality`.
- Documentation generation with warnings as errors and `mix hex.build` passed.
- All **202 scale cases** passed result, copied-term, and cleanup checks on
  Elixir 1.20.3 / OTP 29. No owned helper remained in any resource sample.
- All **84 smoke cases** passed on Elixir 1.18.5 / OTP 27.3.4.12. This was a
  compatibility run, not paired timing evidence.

The runtime floor required an isolated Hex archive directory because the
user's normal Hex archive was built for a later OTP release. Floor builds used
`MIX_ARCHIVES=/tmp/jido-core-floor-archives` and `MIX_BUILD_PATH=_build/floor_dev`.
No dependency or global archive was changed.

The standard-library empty-map paths for Rounds 12 and 13 were also checked
in the loaded OTP 27 abstract code. Both empty-side cases return the existing
other map without visiting entries.

Commands:

```sh
ERL_FLAGS='+S 2:2' mix test --cover test/jido test/jido_test test/integration --include integration --include flaky --seed 0
ERL_FLAGS='+S 2:2' mix test test/examples --include example --include integration --include flaky --seed 0
ERL_FLAGS='+S 2:2' mix quality
ERL_FLAGS='+S 2:2' mix docs --no-open --warnings-as-errors
ERL_FLAGS='+S 2:2' mix hex.build
ERL_FLAGS='+S 2:2' mix run bench/run.exs --profile scale --output bench/results/phase-34-scale
```

Local logs: `/tmp/jido-phase-34-{coverage,examples,quality,docs,package,floor,scale}.log`.
Reports: `bench/results/phase-34-scale` and `bench/results/phase-34-floor-smoke`.
