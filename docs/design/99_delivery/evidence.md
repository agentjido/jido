# Local delivery evidence

## Candidate identity

- Date: 2026-09-09.
- Branch: `v3-spike`.
- Candidate: the commit that contains this record.
- Candidate parent: `ed0a410d`.
- Package set: [package matrix](package-matrix.md).
- Scope: [scope ledger](scope-ledger.md).

The refreshed quality, example, research, and documentation checks ran on
`ed0a410d`, before this evidence-only commit. The code, tests, public guides,
and design records in that tree are the same inputs used by those checks.
Other rows retain prior release evidence and are marked for refresh before a
new publication decision.

## Results

| Gate | Command | Runtime | Result |
| --- | --- | --- | --- |
| Core quality | `mix quality` | Elixir 1.20.3, OTP 29.0.5 | Format, warnings-as-errors compile, Credo, and Dialyzer pass; 1,202 tests pass and 1 is excluded. |
| Core coverage | `mix test --cover test/jido --include flaky --seed 0` | Elixir 1.20.3, OTP 29.0.5 | Prior candidate: 1,195 pass, 1 excluded; total 91.2%. Refresh before release approval. |
| Support floor | `mise exec erlang@27.3.4.12 elixir@1.18.5-otp-27 -- mix test test/jido --include flaky --seed 0` | Elixir 1.18.5, OTP 27.3.4.12 | Prior candidate: 1,196 pass, 1 excluded. Refresh before release approval. |
| Bench contracts | `mix benchmarks --seed 0` | Elixir 1.20.3, OTP 29.0.5 | Prior candidate: 7 pass. Refresh before release approval. |
| Examples | `mix examples --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 306 pass; no skips. |
| Research subset | `mix test test/examples/99_research --include example --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 48 pass; no skips. |
| Documentation | `mix docs --no-open -f html --warnings-as-errors` | Elixir 1.20.3, OTP 29.0.5 | Pass. |
| Hex package | `mix hex.build --unpack --output <temporary-package>` | Elixir 1.20.3, OTP 29.0.5 | Prior candidate passed. Refresh before release approval. |

## Package inspection

The unpacked package contains `lib`, `mix.exs`, `.formatter.exs`, `README.md`,
`usage-rules.md`, `guides`, and `LICENSE`. It excludes tests, examples,
benchmarks, design records, build output, and repository metadata. The package
metadata selects Hex `jido_action 3.0.0-beta.9` and Hex `jido_signal
3.0.0-beta.4`.

## Exceptions and external gates

No local gate exception is active. `DIST-03` is the only excluded assertion and
is a scope disposition, not a hidden pass. Exact-commit CI, refreshed secondary
release gates, and human publication approval are not available from this
result, so this record does not claim them.
