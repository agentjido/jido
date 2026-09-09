# Local delivery evidence

## Candidate identity

- Date: 2026-09-09.
- Branch: `v3-spike`.
- Candidate: the commit that contains this record.
- Candidate parent: `66c4d054`.
- Package set: [package matrix](package-matrix.md).
- Scope: [scope ledger](scope-ledger.md).

The checks ran on the complete candidate tree before its single delivery
commit. The commit contains that same tree. The final repository check confirms
the commit identity and a clean worktree.

## Results

| Gate | Command | Runtime | Result |
| --- | --- | --- | --- |
| Core quality | `mix quality` | Elixir 1.20.3, OTP 29.0.5 | Format, warnings-as-errors compile, Credo, and Dialyzer pass; 1,195 tests pass and 1 is excluded. |
| Core coverage | `mix test --cover test/jido --include flaky --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 1,195 pass, 1 excluded; total 91.2%, above 90%. |
| Support floor | `mise exec erlang@27.3.4.12 elixir@1.18.5-otp-27 -- mix test test/jido --include flaky --seed 0` | Elixir 1.18.5, OTP 27.3.4.12 | 1,196 pass, 1 excluded. |
| Bench contracts | `mix benchmarks --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 7 pass. |
| Examples | `mix examples --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 293 pass, 3 skipped. |
| Research subset | `mix test test/examples/99_research --include example --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 42 pass, 3 skipped. |
| Documentation | `mix docs --no-open -f html --warnings-as-errors` | Elixir 1.20.3, OTP 29.0.5 | Pass. |
| Hex package | `mix hex.build --unpack --output <temporary-package>` | Elixir 1.20.3, OTP 29.0.5 | Pass; production package contents inspected. |
| Public consumer | `JIDO_CANDIDATE_PATH=<temporary-package> MIX_BUILD_PATH=<temporary-build> MIX_DEPS_PATH=<temporary-deps> mix deps.get` then `mix test --seed 0` | Elixir 1.20.3, OTP 29.0.5 | 1 pass. |

## Package inspection

The unpacked package contains `lib`, `mix.exs`, `.formatter.exs`, `README.md`,
`usage-rules.md`, `guides`, and `LICENSE`. It excludes tests, examples,
benchmarks, integration fixtures, design records, build output, and repository
metadata. The package metadata selects Hex `jido_action 3.0.0-beta.9` and Hex
`jido_signal 3.0.0-beta.4`.

## Exceptions and external gates

No local gate exception is active. The three research skips and `DIST-03` are
scope dispositions, not hidden passes. Exact-commit CI and human publication
approval are not available from the local worktree, so this record does not
claim either result.
