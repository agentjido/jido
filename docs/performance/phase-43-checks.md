# Checks after 43 idea decisions

The cycle has 43 completed decisions: twelve accepted fixes, eight measured
rejections, and 23 source or contract rejections. Seven rounds remain, including
the final 50-pair combined run.

[Round 34](round-34-codec-map.md) replaces the temporary document key/value list
with direct map iteration. Valid large-map scan time fell by 16% to 27% in all
five pairs. A separate allocation profile confirmed less heap allocation in
all five investigated cases. The report records four sampled peak increases;
this change does not lower peak memory for every map size or codec workload.

## Checks

Runtime commit: `6e2b638e`. Test commit: `5d476e88`.

- Core, integration, and flaky selection: **898 passed**, one existing DIST-03
  exclusion. Core coverage: **83.5%**, above the 80% gate. Examples, test
  fixtures, and benchmark helpers stay outside that gate.
- Separate example selection: **272 passed, 11 failed**. Failure names and
  modules exactly match the prior run.
- Format, warnings-as-errors compile, strict warning lint, Dialyzer,
  documentation, and package checks passed.
- All **253 scale cases** passed on Elixir 1.20.3 / OTP 29, including result,
  copied-term, and cleanup checks. No owned helper remained.
- All **132 smoke cases** passed on Elixir 1.18.5 / OTP 27.3.4.12. The two new
  codec boundary tests also passed on this minimum version. Those tests cover
  exact limits and error fields, except the call-site stack trace.
- The focused codec, topology, Agent, and benchmark selection passed **149 tests**.

Logs: `/tmp/jido-phase-43-{coverage,examples,quality,docs,package,scale,floor}.log`
and `/tmp/jido-phase-43-floor-codec.log`.
Reports: `bench/results/phase-43-scale` and `bench/results/phase-43-floor`.
Profiles contain 132 smoke, 212 short, and 253 scale cases.
