# Core performance cycle: checks after 18 decisions

Rounds 07, 08, and 09 were accepted after measurement and checks. Five ideas
were rejected after measurement. Ten were rejected by source inspection. The
remaining 32 ideas have not finished. Measurement pairs are not idea rounds.

## Runtime changes

- Generate Audit record IDs only when absent.
- Read the clock only when an Audit timestamp is absent.
- Keep an existing bounded Audit buffer on empty updates. Trim an oversized
  buffer using its known count.

The Thread runtime and nonempty Audit updates remain unchanged. Rejected
runtime candidates are preserved as [trial patches](trials/README.md).

## Checks

Measured and checked revision: `616dfbd3`.

- Core tests: **890 passed, one existing DIST-03 exclusion**.
- Core coverage: **83.4%**, above the unchanged 80% gate. Examples, test fixtures,
  and benchmark helpers are excluded from the coverage calculation.
- Example tests: **272 passed, 11 failed**. These are the same research-example
  failures recorded before this work. No additional test was excluded.
- All **149 short** and **190 scale** cases passed result, transfer, and cleanup
  checks in separate runs on an idle host.
- All **72 smoke** cases passed on **Elixir 1.18.5 / OTP 27.3.4.12**. This was a
  compatibility check run alongside quality checks; its time samples are not
  used for performance claims.
- Format, compile with warnings as errors, strict warning lint, Dialyzer, docs
  with warnings as errors, and Hex package build passed.

The short and scale reports are in `bench/results/cycle-short` and `cycle-scale`.
The runtime-floor report is in `cycle-floor-smoke`. Acceptance evidence remains
in the individual round reports. Do not compare reports with different tool
hashes or settings.

Runtime SHA-256: `f808afbd20ec04e8f9e8d65a9c2ac2d02845823b613bd0d4314f12c969049196`.
Tool SHA-256: `c06a4c848267f8a5732151c2947b762ac84fc7f93c19e10d88c83cd20dfe48ab`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.

Performance host: Apple M1 Max, Elixir 1.20.3, OTP 29, two schedulers, Mix dev.
