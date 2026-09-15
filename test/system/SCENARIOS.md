# System scenario implementation record

`TODO.md` tracks completed probes and remaining work. This file records
implementation status and test evidence. A passing probe establishes only the
contract named by the probe. Durable Topology target recovery now passes for
the tested restarts; it does not establish cluster-wide ownership or exactly-once
external effects.

## Added scenarios

| Area | Implementation | Evidence |
| --- | --- | --- |
| Repeated recovery | `support/scenarios/recovery.exs` | Two confirmation write failures, four effect attempts, one deduplicated record; passes on ETS, File, SQLite |
| Late storage request | `support/scenarios/recovery.exs` | Captured old revision rejected after replacement or tombstone; passes on ETS, File, SQLite |
| Cancellation and deadlines | `support/scenarios/execution.exs` | Pre-commit cancellation/Turn timeout cannot save a late result; queued cancellation/caller timeout cannot reverse an accepted commit; passes on ETS, File, SQLite |
| Disk faults | `runtime/file_storage_test.exs` | Real corrupt bytes, directory permission error, rename failure, physical delete failure; no in-memory substitutes |
| Restore boundaries | `support/scenarios/restoration.exs` | Both restore modes reject an unsupported Plugin record; a tombstone during a held read prevents activation |
| Independent state oracle | `support/turn_model.exs` | Mixed success, rejection, cancellation, timeout, conflict, deletion, restart, and uncertain writes; seeded generation and bounded failure reduction |
| Combined overload | `support/scenarios/overload.exs` | Caller timeout, full queue, rejected calls/cast, Bus replacement, and worker death; exact request and event accounting |
| Immediate supervisor replacement | `runtime/supervision_test.exs` | Held old child, bounded name-release wait, replacement tree and unchanged checkpoint; passes with local Jido fix |
| Redis storage faults | `services/redis_faults_test.exs` | Real SIGKILL/AOF restart and TCP proxy reply loss after Lua execution; both pass |
| PostgreSQL | `services/postgres_test.exs` | Real isolated Docker database; same 25 Agent/Topology scenarios pass |
| Bedrock storage faults | `services/bedrock_faults_test.exs` | Paused; earlier Bedrock 0.7.2 runs passed restarts and coordinator/log replacement, while unassisted placeholder cleanup failed |
| Real trace export | `runtime/open_telemetry_test.exs` | Four SDK tests pass: exported parentage, exporter failure isolation, handler failure isolation, and paired overhead measurements |
| Metrics and logs | `runtime/observability_test.exs` | Public counters, host revision gauge, structured log identity and payload redaction |
| Plugin commit notification | `runtime/commit_projection_test.exs` | Exact live and saved owned-state/revision pairs, unchanged Turns, required restore without notification replay, scoped hook logs, balanced semantic spans, and resource cleanup; passes on ETS, File, SQLite |
| Composed Topology | `support/scenarios/topology.exs` | Included teams, logical ownership, exact local placement and shared Bus replacement; latest run passes, earlier readiness timeout needs repeats |
| Partial Topology cleanup | `runtime/topology_cleanup_test.exs` | Real resource ownership conflict, accepted added members, control-tree failure during cleanup; `SYSTEM-TOPOLOGY-03` passes |
| Signal journey | `runtime/signal_journey_test.exs` | JSON validation and explicit key conversion, Bus/Router, Action/Flow, commit, Directive, failed acknowledgement and replay; latest run passes, earlier `SYSTEM-BUS-01` timeout needs repeats |
| Peer reconstruction | `runtime/peers_test.exs` | Three actual BEAM SIGKILLs with required File restores, held-work interruption and witnessed node loss; passes |
| Sustained peer partitions | `runtime/peers_test.exs` | Remote held Turn cancellation, child/task cleanup, closed request, lost startup reply, explicit replacement and stale lifecycle rejection; independent standard-IO control and blocked data-link cookies; both pass |
| Shared-store stale write | `services/redis_partition_test.exs` | Connected peers partition while an old Agent holds work; another Agent commits revision two through the same real Redis store; old write loses CAS after rejoin; passes |
| Cluster ownership | `runtime/peers_test.exs` | Same logical identity activates on connected peers with separate stores; exposes `SYSTEM-CLUSTER-01`, not a distributed File guarantee |
| Long seeded burn-in | `burn_in.exs` and `support/turn_model.exs` | Fresh Mix processes, independent oracle, replay artifacts, process/memory/mailbox/record/byte growth checks |
| Bedrock transaction faults | `services/bedrock_transactions_test.exs` | Paused; earlier resolver-conflict and reply-loss runs passed saved-state and effect checks |
| Strict Bedrock peers | `services/bedrock_strict_test.exs` | Paused; earlier three-node startup failed before node-loss durability checks |
| Bedrock/MinIO | `services/minio/snapshots_test.exs` | Paused; earlier native upload and cold rebuild failed. Direct S3 tests remain active. |
| Direct S3/MinIO | `services/minio/s3_test.exs`, `services/minio/s3_pressure_test.exs`, and `run_s3_minio_local.py` | Real conditional object writes, shared Agent scenarios, 48 competing creates, eight rounds each of token and checkpoint writes, and an accepted write with a lost reply; pressure tests pass |
| Compact run evidence | `support/report.exs` | Per-run JSON in ignored `tmp/system-runs`; revisions, effects, event counts, resource counts, and interrupted operation IDs |

The ordered fault queue retains the simple single-fault API. The effect sink
records each attempt separately from its deduplicated records. Synchronization
uses messages, monitors, telemetry, and actual timeout responses, not sleeps.

## Open contracts and recent fixes

- `SYSTEM-TOPOLOGY-01/02/03` now pass. Accepted targets restore after Runtime
  and whole-Jido replacement, and Controller cleanup stops owned added Agents.
  Full BEAM target reconstruction and explicit target deletion/replacement
  remain separate work in `TODO.md`.
- File returns raw OS errors. Persistence classifies an unclassified write
  error as indeterminate and stops the Agent. A failed temporary write does not
  currently produce the narrower `:rejected` classification.
- `SYSTEM-SUPERVISION-01` passes with a bounded wait for old Jido
  children to release registered names. This needs review and repeated runs.
- `SYSTEM-BEDROCK-01`: the placeholder survives unassisted cluster shutdown.
- All five real Bedrock service modules and the MinIO snapshot module are
  skipped by user direction while upstream fixes are pending. Their assertions
  remain in source. Core adapter unit tests and non-Bedrock services still run.
- `SYSTEM-BEDROCK-02` passed before the service suite was paused after the
  upgrade to Bedrock 0.7.2.
- `SYSTEM-CLUSTER-01`: separate local registries permit two cluster owners.
  The user directed a skip because cluster-exclusive ownership is outside the
  V3 beta scope. The probe stays in source, but it is not in `mix test.all` or
  CI; the approved core DIST-03 skip is unchanged.
- `SYSTEM-BUS-01` and shared-Bus replacement readiness pass in the latest
  full run with nonblocking Client delivery. Earlier timing failures
  still need repeated fresh-BEAM runs; no adapter defect is established.
- `SYSTEM-BEDROCK-03`: native S3 snapshot upload passes an iolist to ExAws,
  which attempts JSON encoding and raises `Jason.EncodeError`. The test's
  binary-upload control uses the same real compacted files and real MinIO.
- `SYSTEM-BEDROCK-04`: strict peer startup fails when Link queries a Foreman
  that has not started. The three-node durability and node-loss assertions
  are implemented but have not been reached. No retry or startup delay hides it.
- `SYSTEM-BEDROCK-05`: after the binary-upload control, the rebuilt cluster
  loads its bootstrap but does not publish a ready layout within the existing
  30-second fixture deadline. Coordinator metadata and log WAL are retained;
  the original materializer files are preserved as evidence. Snapshot recovery
  is not proved.
- The new target store covers the selected local and service restart paths,
  not cluster-wide owner authority or every target lifecycle rule. Service
  prerequisites must fail explicitly, not select a fake adapter or silently
  skip a scenario.

## Verification

| Check | Result |
| --- | --- |
| `mix quality`, 2026-09-14 | 1106 core tests pass; format, warnings-as-errors compile, Credo, and Dialyzer pass |
| `mix quality`, Plugin hook work, 2026-09-15 | Final standalone run: 1,149 core tests pass, 29 excluded; format, warnings-as-errors compile, Credo, and Dialyzer pass. Earlier Scheduler recovery CAS conflict is recorded in TODO. |
| `mix test.all --cover`, Plugin hook work, 2026-09-15 | Initial run: 2,062/2,063 pass with one remote lifecycle peer timeout. Final standalone run: 2,063 pass, two existing skips, 115 excluded; 93.7% coverage. Earlier failure remains recorded in TODO. |
| Focused hook, ownership, and example checks on Elixir 1.18.5 / OTP 27 | 27 tests pass; normal Hex dependencies retained. Docs build with warnings as errors on the current runtime. |
| `mix test.authoring`, 2026-09-14 | 523/523 pass |
| `mix test.bench`, 2026-09-14 | 7/7 benchmark contract tests pass |
| `mix test.system`, 2026-09-14, seed 0 | Last separate run before the skip: 112/113 pass; rerun pending. The full suite includes this selection. |
| `mix test.services`, 2026-09-14, seed 0 | 53 pass, 33 skipped; all real Bedrock service modules paused, Redis and PostgreSQL active |
| Focused sustained partition probes | Two local peer tests pass with held Turn and late spawn; shared-Redis stale-write test passes with real CAS |
| `mix test.all --cover`, 2026-09-14 | 2,015 pass, 2 skipped, 115 excluded; 93.5% coverage. `SYSTEM-CLUSTER-01` is one of the skips. |
| Full MinIO profile, 2026-09-14, seed 0 | First run: 27/28 pass, one direct S3 Topology readiness timeout, one Bedrock skip. Immediate repeat: 28 pass, one Bedrock skip. The owned bucket and objects were removed and the server stopped. Earlier Bedrock run recorded cold-rebuild failure and two native-upload encoding errors. |
| Direct S3 MinIO pressure repeats, seed 0 | Four fresh local runs each pass both tests against MinIO `RELEASE.2025-10-15T17-29-55Z` |
| Burn-in, two runs, 20 rounds, seeds 93 and 94 | All eight selected tests pass; 1086 model commands and six BEAM crashes across both runs |
| Redis Bus readiness, fresh runs at seeds 0, 7 and 19 | All pass with the unchanged readiness call; original intermittent failure remains unexplained |
| Observability and SDK focused run | All seven pass |
| Redis actual storage fault focused run | Both pass |
| Bedrock transaction fault focused run | Both pass |

Every selected service uses its real backend. Missing prerequisites fail setup.
MinIO is not selected by the base service alias. Redis, PostgreSQL, Bedrock and
MinIO remain outside `mix test.all`. No CI job was added.

## Remaining decisions, not test scaffolding

The scenario families in the TODO now have runnable tests. This does not mean
every downstream assertion has passed: strict Bedrock startup and MinIO rebuild
block their later checks. Target deletion/replacement rules and exclusive
cluster authority remain design work. The Jido fixes and dependency upgrade
are committed locally but need review and repeated runs before the earlier
timing failures can be called resolved.

The probes do not claim exclusive cluster ownership or exactly-once effects.
