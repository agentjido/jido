# Jido 3.0.0-beta.2 release record

Prepared on 2026-10-19 from `release/v3`, source baseline `50788a22`,
with the recovery fix and test repairs described below.
This record covers the new Hex dependency set. Jido beta.2 was published on
2026-10-19 from tag `v3.0.0-beta.2`, commit `eb5f5818`.
[Hex package](https://hex.pm/packages/jido/3.0.0-beta.2) and
[GitHub prerelease](https://github.com/agentjido/jido/releases/tag/v3.0.0-beta.2).

## Package set

| Package | Hex version |
| --- | --- |
| jido_action | 3.0.0-beta.21 |
| jido_signal | 3.0.0-beta.5 |
| runic | 0.1.0-alpha.12 |
| covenant (development and test) | 0.2.0 |

No sibling path or Git dependency is required for the release candidate.
Runic local `main` tracks `zblanco/runic` upstream at `b3a6e7e`. Its only
library difference from Hex alpha.12 is documentation in `workflow/events.ex`.
Covenant's local library files match Hex 0.2.0.

## Checks

| Check | Runtime | Result |
| --- | --- | --- |
| `mix quality` | Elixir 1.20.4 / OTP 29.1 | Pass: format, compile, lint, 298 contract tests, 147/147 obligations, Dialyzer, and 1,028 core tests |
| `mix test.all --cover --warnings-as-errors` | Elixir 1.20.4 / OTP 29.1 | Pass: 1,733 passed, one approved skip, 134 excluded; 93.7% coverage |
| `mix test.all --warnings-as-errors` | Elixir 1.18.5 / OTP 27.3.4.12 | Pass: 1,733 passed, 134 excluded, one approved cluster-authority skip |
| Changed Plugin timeout tests | Elixir 1.18.5 / OTP 27.3.4.12 | Pass: 38 tests after the test-only monitor repair |
| `mix docs --no-open -f html --warnings-as-errors` | Elixir 1.20.4 / OTP 29.1 | Pass |
| `mix hex.audit` | Elixir 1.20.4 / OTP 29.1 | Pass: no retired or advisory packages |
| `mix hex.build --unpack` | Elixir 1.20.4 / OTP 29.1 | Pass: beta.2 package with Hex dependencies and no overrides |
| Fresh unpacked production package, `mix deps.get` and `mix compile --warnings-as-errors` | Elixir 1.20.4 / OTP 29.1 | Pass, including the recovery fix |
| Exact-tag CI | OTP 27 / Elixir 1.18; OTP 28 / Elixir 1.18 and 1.19; OTP 29 / Elixir 1.20 | Pass: all required jobs |
| Publish workflow preflight | Elixir 1.20 / OTP 29 | Pass: quality, 1,733 tests passed, one approved skip, 134 excluded, 93.8% coverage, docs, and Hex audit |
| Published archive and documentation | Hex beta.2 | Pass: all 254 packaged files match the release tag, archive checksum matches Hex metadata, documentation returns HTTP 200 |

[Exact-tag CI](https://github.com/agentjido/jido/actions/runs/39292405561) and
[publish workflow, attempt 2](https://github.com/agentjido/jido/actions/runs/39293472383/attempts/2).

The first quality run found an asynchronous output assertion with a 100 ms
limit. The call acknowledges commit before Directive delivery. The test now
waits for the output message with a five-second limit.

The first floor run found concurrent native scope closure during recovery.
On OTP 27, normal scope termination could make `GenServer.stop/3` exit through
`:sys.terminate`. Recovery then reported Plugin startup failure. Jido now uses
Runic's native `confirm_close/1`, clears ownership only after confirmed normal
closure, and accepts an already-closed scope. An abnormal scope exit remains
an error. A deterministic regression failed before the fix and passes after it.

A later contract run found a Plugin startup test that could install a monitor
after its startup deadline. The test now reads the worker from the Plugin
startup event. It does not wait on the supervisor behind the blocked sibling
start. The original startup timeout and cleanup assertions remain.

CI also found that the rejected-checkpoint recovery test could call `thaw`
before the old activation stopped. Commit `eb5f5818` adds an activation monitor
and waits for shutdown before restore. It preserves the checkpoint and replay
assertions.

Publish attempt 1 found a similar ordering assumption in a system test. A failed
restore can return its worker error before the activation root exits. The shared
pool assertion now waits for root shutdown before checking the child count.
This test fixture fix is a separate commit, `5872552f`; it does not change the
published tag or any Hex package file. All 60 storage and recovery scenarios,
the full local suite, and
[follow-up CI](https://github.com/agentjido/jido/actions/runs/39295441965) passed.
Publish attempt 2 passed all checks on the existing release tag before upload.

The published Action beta.21 archive matches all 130 release-tag files.
Its release CI passed 1,158 tests and properties with 94.89% coverage.
[Action publish run](https://github.com/agentjido/jido_action/actions/runs/39276702349).

## Code quality assessment

The package boundaries are explicit: Action owns executable Flow behavior,
Signal owns messages, and Jido owns AgentServer wait policy and persistence.
Action has no Signal dependency. The wait integration uses native Runic
execution and checkpoint data.

The principal maintenance concern is the 4,466-line `lib/jido/agent_server.ex`
module. Its serial event handling, commit, cleanup, and recovery paths share
one large module. Keep changes small and preserve contract tests. A passing
coverage total does not remove this review cost.

## Release limits

- The normal suite excludes external Redis, PostgreSQL, Bedrock, and MinIO
  service profiles. It does not prove those service contracts.
- Bedrock strict startup and snapshot recovery have open evidence gaps. The
  maintainer authorized beta.2 publication on 2026-10-19. Publication does not
  supply passing evidence for the paused service profiles.
- The cluster-exclusive ownership research probe remains skipped by user
  direction. Core does not supply distributed fencing or exactly-once effect
  delivery.
- Historical design and delivery records describe older source revisions.
  Use this record for beta.2 checks and the migration guide for API changes.
- Exact-tag CI and the publish workflow passed. The published tag remains at
  `eb5f5818`. Release history was generated with GitOps.

See [migration](../guides/migration.md),
[service test policy](../test/system/README.md), and the historical
[beta.1 evidence](design/99_delivery/evidence.md).
