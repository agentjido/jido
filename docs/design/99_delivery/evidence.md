# Beta preparation evidence

## Candidate identity

- Preparation date: 2026-09-14.
- Branch: `release/v3`, cut from `v3-spike` at `23ecf0fd`.
- Source baseline: `4835d71a`, which fixes the Topology upgrade example race.
  This record adds release documentation, not production or test code. The
  release workflow must verify the final candidate commit before publication.
- Package version: `3.0.0-beta.1`, approved for publication with the two
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
| Exact-source CI release preflight | [Release run 34882608048](https://github.com/agentjido/jido/actions/runs/34882608048), `prepare` dry run | Elixir 1.20.3, OTP 29.0.5; commit `4835d71a` | Pass: quality, full suite, docs, Hex audit, and release preparation. This record changes documentation; the publication workflow must validate its final commit. |

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
4. The source-baseline CI preflight passes. The release workflow must pass on
   the final candidate commit before it creates a tag or publishes to Hex.

The user directed the cluster and Bedrock test skips. The human release
approver approved `BETA1-BEDROCK` and `BETA1-FLOOR` on 2026-09-14 for this
beta only. This record does not claim publication, Bedrock durability, or a
passing Elixir 1.18/OTP 27 result.
