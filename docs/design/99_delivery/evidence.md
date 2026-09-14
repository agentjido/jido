# Beta.1 release evidence

## Candidate identity

- Preparation date: 2026-09-14.
- Branch: `release/v3`, cut from `v3-spike` at `23ecf0fd`.
- Tagged release commit: `5413df1132859e702a62d48486caf2da61f499f3`
  on `release/v3`. It includes source baseline `4835d71a`, which fixes the
  Topology upgrade example race, and the approved release records.
- Package version: Hex `3.0.0-beta.1`, published 2026-09-14 with the two
  exceptions in the [scope ledger](scope-ledger.md).
- Dependency set: [package matrix](package-matrix.md).
- Release scope: [scope ledger](scope-ledger.md), including the optional
  Bedrock adapter.

## Current local results

These are observed results. The human release approver accepted the two
beta.1-only exceptions in the scope ledger. Skipped and failed checks remain
unproved despite that approval.

| Gate | Command or profile | Runtime | Result |
| --- | --- | --- | --- |
| Core quality | `mix quality` | Elixir 1.20.3, OTP 29.0.5 | Pass: format, compile, Credo, Dialyzer, and 1,106 core tests. |
| Core-only coverage | `mix test --cover test/jido --include flaky --seed 0` | Elixir 1.20.3, OTP 29.0.5 | Pass: 1,106 tests, 28 excluded; 92.4% total coverage for this selection, above the 90% gate. |
| Authoring | `mix test.authoring` | Elixir 1.20.3, OTP 29.0.5 | Pass: 523/523. |
| Examples | `mix test.examples` | Elixir 1.20.3, OTP 29.0.5 | Pass: 240/240. |
| Benchmark contracts | `mix test.bench` | Elixir 1.20.3, OTP 29.0.5 | Pass: 7/7. This is not a sustained load result. |
| Local system | `mix test.system` | Elixir 1.20.3, OTP 29.0.5 | Last separate run before the skip failed 112/113. The current full suite includes the system selection; a separate rerun is pending. |
| Full local suite and coverage | `mix test.all --cover` | Elixir 1.20.3, OTP 29.0.5 | Pass: 2,015 passed, 2 skipped, 115 excluded; 93.5% coverage. `SYSTEM-CLUSTER-01` is skipped by user direction. |
| External services | `mix test.services` | Elixir 1.20.3, OTP 29.0.5 | Pass with skips: 53 passed, 33 skipped. All five real Bedrock service modules are paused; Redis and PostgreSQL remain active. |
| MinIO snapshot profile | Owned local MinIO runner | Elixir 1.20.3, OTP 29.0.5 | First run: 27/28 passed, 1 Bedrock skip, 1 direct S3 Topology readiness timeout. Immediate repeat: 28 passed, 1 Bedrock skip. Prior Bedrock run failed cold rebuild and recorded native-upload `Jason.EncodeError` results. |
| Support floor | `mise exec erlang@27.3.4.12 elixir@1.18.5-otp-27 -- mix test test/jido --include flaky --seed 0` | Elixir 1.18.5, OTP 27.3.4.12 | Fail before tests: example `07_08_placement_policy/move.ex` cannot expand its Directive struct during compilation. |
| Docs | `mix docs --no-open -f html --warnings-as-errors` | Elixir 1.20.3, OTP 29.0.5 | Pass. |
| Hex publish dry run | `mix hex.publish --dry-run` | Elixir 1.20.3, OTP 29.0.5 | Package build and checks complete, then command exits 1 because no Hex user is authenticated. No upload or publication occurred. |
| CI Hex dry run | [Release run 34880522567](https://github.com/agentjido/jido/actions/runs/34880522567), `mix hex.publish --dry-run --yes` | Elixir 1.20.3, OTP 29.0.5; commit `1b657df0` | Pass: package and docs built. The normal Release job was skipped. |
| Hex package inspection | `mix hex.build --unpack --output /tmp/jido-hex-preview.GDGI1G` | Elixir 1.20.3, OTP 29.0.5 | Pass. Unpacked package contains `lib`, `mix.exs`, `.formatter.exs`, `README.md`, `usage-rules.md`, `guides`, and `LICENSE`; it excludes tests, examples, and design records. |
| Fresh package compilation | `MIX_ENV=prod mix deps.get` and `MIX_ENV=prod mix compile --warnings-as-errors` in the unpacked package | Elixir 1.20.3, OTP 29.0.5 | Pass against newly fetched Hex dependencies. |
| Exact-source CI release preflight | [Release run 34885657403](https://github.com/agentjido/jido/actions/runs/34885657403), `prepare` | Elixir 1.20.3, OTP 29.0.5; parent commit `0a239aa4` | Pass: quality, full suite, docs, Hex audit, release commit and tag push, and publish dispatch. |
| Tagged-commit CI publish | [Release run 34886362229](https://github.com/agentjido/jido/actions/runs/34886362229), `publish` | Elixir 1.20.3, OTP 29.0.5; tagged commit `5413df11` | Pass: preflight, Hex upload, registry confirmation, and GitHub release creation. The GitHub release was then marked as a prerelease targeting `release/v3`. |

The prior evidence record reported older candidate results and selected Hex
`jido_action 3.0.0-beta.9`. Those results do not prove this candidate, which
selects Hex `jido_action 3.0.0-beta.11` and `jido_signal 3.0.0-beta.4`.

## Accepted beta.1 limits and final check

1. The included Bedrock profile still lacks passing strict startup and
   MinIO-backed snapshot recovery on a published dependency set. All real
   Bedrock service tests are skipped by user direction; passing profiles with
   skips do not prove those contracts. Local Bedrock fixes are not in Hex
   0.7.2. See [Bedrock issue 319](https://github.com/bedrock-kv/bedrock/issues/319)
   and [Jido issue 370](https://github.com/agentjido/jido/issues/370).
2. The direct S3 Topology readiness test timed out once on the latest MinIO
   profile and passed on an immediate repeat. The cause is not established.
3. The Elixir 1.18.5/OTP 27 support-floor run fails during example Directive
   compilation. Core tests did not run under that runtime.
4. The prepare and publish workflows passed. The beta tag and Hex package
   exist; this does not close the two beta.1-only exceptions.

The user directed the cluster and Bedrock test skips. The human release
approver approved `BETA1-BEDROCK` and `BETA1-FLOOR` on 2026-09-14 for this
beta only. This record claims publication, not Bedrock durability or a
passing Elixir 1.18/OTP 27 result.
