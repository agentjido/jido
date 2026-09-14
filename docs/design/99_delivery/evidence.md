# Beta preparation evidence

## Candidate identity

- Preparation date: 2026-09-14.
- Branch: `release/v3`, cut from `v3-spike` at `23ecf0fd`.
- Local full-suite baseline: the test skip and release workflow in this branch;
  this record adds documentation only. The CI Hex dry run used `c147595e`
  before the test skip. Exact-commit release verification remains open.
- Package version: `3.0.0-beta.1`, not published.
- Dependency set: [package matrix](package-matrix.md).
- Release scope: [scope ledger](scope-ledger.md), including the optional
  Bedrock adapter.

## Current local results

These are observed results, not release approval. A failed or unrun gate is
open even when another gate passes.

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
| CI Hex dry run | [Release run 34876701594](https://github.com/agentjido/jido/actions/runs/34876701594), `mix hex.publish --dry-run --yes` | Elixir 1.20.3, OTP 29.0.5; commit `c147595e` | Pass on the release branch before the test skip: package and docs built. The normal Release job was skipped. Hex still has no Jido `3.0.0-beta.1` release. |
| Hex package inspection | `mix hex.build --unpack --output /tmp/jido-hex-preview.GDGI1G` | Elixir 1.20.3, OTP 29.0.5 | Pass. Unpacked package contains `lib`, `mix.exs`, `.formatter.exs`, `README.md`, `usage-rules.md`, `guides`, and `LICENSE`; it excludes tests, examples, and design records. |
| Fresh package compilation | `MIX_ENV=prod mix deps.get` and `MIX_ENV=prod mix compile --warnings-as-errors` in the unpacked package | Elixir 1.20.3, OTP 29.0.5 | Pass against newly fetched Hex dependencies. |
| Exact-commit CI | Pull request or merge-group workflow | GitHub | Pending. A `release/v3` push alone does not run the configured CI workflow. |

The prior evidence record reported older candidate results and selected Hex
`jido_action 3.0.0-beta.9`. Those results do not prove this candidate, which
selects Hex `jido_action 3.0.0-beta.11` and `jido_signal 3.0.0-beta.4`.

## Open release blockers

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
4. The CI Hex dry run passes, but it is not the full release validation. A
   passing exact-commit CI result for all required gates and human release
   approval remain open.

The user directed the cluster and Bedrock test skips. No Bedrock release-gate
waiver or support-floor exception is approved. This record does not claim
publication or a Bedrock durability result.
