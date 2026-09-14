# Beta preparation evidence

## Candidate identity

- Preparation date: 2026-09-14.
- Branch: `v3-spike`.
- Source code and test baseline: `8d7e26c3`. The commit that contains this
  record changes release text only; exact-commit release verification remains
  open.
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
| Local system | `mix test.system` | Elixir 1.20.3, OTP 29.0.5 | Fail: 112/113 pass; only `SYSTEM-CLUSTER-01` fails. |
| Full local suite and coverage | `mix test.all --cover` | Elixir 1.20.3, OTP 29.0.5 | Fail: 2,015/2,016 pass; `SYSTEM-CLUSTER-01` fails; 1 skipped, 115 excluded; total coverage 93.5%. |
| External services | `mix test.services` | Elixir 1.20.3, OTP 29.0.5 | Fail: 84/86 pass; `SYSTEM-BEDROCK-01` and `SYSTEM-BEDROCK-04` fail against Hex Bedrock 0.7.2. |
| MinIO snapshot profile | Owned local MinIO runner | Elixir 1.20.3, OTP 29.0.5 | Fail: 28/29 pass; `SYSTEM-BEDROCK-05` fails. Native upload also records two `Jason.EncodeError` results in `SYSTEM-BEDROCK-03`. Direct S3 cases pass. |
| Support floor | `mise exec erlang@27.3.4.12 elixir@1.18.5-otp-27 -- mix test test/jido --include flaky --seed 0` | Elixir 1.18.5, OTP 27.3.4.12 | Fail before tests: example `07_08_placement_policy/move.ex` cannot expand its Directive struct during compilation. |
| Docs | `mix docs --no-open -f html --warnings-as-errors` | Elixir 1.20.3, OTP 29.0.5 | Pass. |
| Hex publish dry run | `mix hex.publish --dry-run` | Elixir 1.20.3, OTP 29.0.5 | Package build and checks complete, then command exits 1 because no Hex user is authenticated. No upload or publication occurred. |
| Hex package inspection | `mix hex.build --unpack --output /tmp/jido-hex-preview.GDGI1G` | Elixir 1.20.3, OTP 29.0.5 | Pass. Unpacked package contains `lib`, `mix.exs`, `.formatter.exs`, `README.md`, `usage-rules.md`, `guides`, and `LICENSE`; it excludes tests, examples, and design records. |
| Fresh package compilation | `MIX_ENV=prod mix deps.get` and `MIX_ENV=prod mix compile --warnings-as-errors` in the unpacked package | Elixir 1.20.3, OTP 29.0.5 | Pass against newly fetched Hex dependencies. |
| Exact-commit CI | Pull request or merge-group workflow | GitHub | Pending. A `v3-spike` push alone does not run the configured workflow. |

The prior evidence record reported older candidate results and selected Hex
`jido_action 3.0.0-beta.9`. Those results do not prove this candidate, which
selects Hex `jido_action 3.0.0-beta.11` and `jido_signal 3.0.0-beta.4`.

## Open release blockers

1. The included Bedrock profile must pass strict startup, replacement, and
   MinIO-backed snapshot recovery on a published dependency set. Local Bedrock
   fixes are not in Hex 0.7.2. See [Bedrock issue 319](https://github.com/bedrock-kv/bedrock/issues/319)
   and [Jido issue 370](https://github.com/agentjido/jido/issues/370).
2. `mix test.all` still fails `SYSTEM-CLUSTER-01`. The test has a `:flaky` tag,
   but the observed failure is repeatable and the tag grants no release
   exception. Its excluded cluster-authority scope and release-gate handling
   need a decision.
3. The Elixir 1.18.5/OTP 27 support-floor run fails during example Directive
   compilation. Core tests did not run under that runtime.
4. The Hex publish dry-run command could not finish its authentication check;
   the independent package build and fresh compilation passed. Exact-commit
   CI and human release approval remain open.

No gate exception is approved. This record does not claim a green candidate,
publication, or a Bedrock durability result.
