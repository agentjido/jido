# System scenario implementation record

`TODO.md` tracks completed probes and remaining work. This file records
implementation status and test evidence. A passing probe establishes only the
contract named by the probe. It does not establish durable Topology targets,
exclusive cluster ownership, or exactly-once external effects.

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
| Immediate supervisor replacement | `runtime/supervision_test.exs` | Enabled `SYSTEM-SUPERVISION-01` failure with held old child, failed-start logs, parent shutdown, and unchanged checkpoint |
| Redis storage faults | `services/redis_faults_test.exs` | Real SIGKILL/AOF restart and TCP proxy reply loss after Lua execution; both pass |
| PostgreSQL | `services/postgres_test.exs` | Real isolated Docker database; same 25 Agent/Topology scenarios; only two known Topology gaps remain |
| Bedrock storage faults | `services/bedrock_faults_test.exs` | Three same-identity restarts pass; live coordinator/log replacement and unassisted placeholder cleanup fail |
| Real trace export | `runtime/open_telemetry_test.exs` | Four SDK tests pass: exported parentage, exporter failure isolation, handler failure isolation, and paired overhead measurements |
| Metrics and logs | `runtime/observability_test.exs` | Public counters, host revision gauge, structured log identity and payload redaction |
| Composed Topology | `support/scenarios/topology.exs` | Included teams, logical ownership, exact local placement and shared Bus replacement; one 2026-09-14 ETS run timed out on replacement readiness |
| Partial Topology cleanup | `runtime/topology_cleanup_test.exs` | Real resource ownership conflict, accepted added members, control-tree failure during cleanup; exposes `SYSTEM-TOPOLOGY-03` |
| Signal journey | `runtime/signal_journey_test.exs` | JSON validation and explicit key conversion, Bus/Router, Action/Flow, commit, Directive, failed acknowledgement and replay; exposes `SYSTEM-BUS-01` |
| Peer reconstruction | `runtime/peers_test.exs` | Three actual BEAM SIGKILLs with required File restores, held-work interruption and witnessed node loss; passes |
| Sustained peer partitions | `runtime/peers_test.exs` | Remote held Turn cancellation, child/task cleanup, closed request, lost startup reply, explicit replacement and stale lifecycle rejection; independent standard-IO control and blocked data-link cookies; both pass |
| Shared-store stale write | `services/redis_partition_test.exs` | Connected peers partition while an old Agent holds work; another Agent commits revision two through the same real Redis store; old write loses CAS after rejoin; passes |
| Cluster ownership | `runtime/peers_test.exs` | Same logical identity activates on connected peers with separate stores; exposes `SYSTEM-CLUSTER-01`, not a distributed File guarantee |
| Long seeded burn-in | `burn_in.exs` and `support/turn_model.exs` | Fresh Mix processes, independent oracle, replay artifacts, process/memory/mailbox/record/byte growth checks |
| Bedrock transaction faults | `services/bedrock_transactions_test.exs` | Real resolver conflict and reply loss after log sync; both pass with saved-state and effect checks |
| Strict Bedrock peers | `services/bedrock_strict_test.exs` | Real three-node bootstrap requests three logs and replicas; startup fails before node-loss durability checks |
| Bedrock/MinIO | `services/minio/snapshots_test.exs` | Explicit endpoint, owned bucket, real compacted snapshots, binary-upload control, cluster/cold-materializer rebuild, owned-object cleanup; upload and rebuild gaps remain |
| Direct S3/MinIO | `services/minio/s3_test.exs`, `services/minio/s3_pressure_test.exs`, and `run_s3_minio_local.py` | Real conditional object writes, shared Agent scenarios, 48 competing creates, eight rounds each of token and checkpoint writes, and an accepted write with a lost reply; pressure tests pass |
| Compact run evidence | `support/report.exs` | Per-run JSON in ignored `tmp/system-runs`; revisions, effects, event counts, resource counts, and interrupted operation IDs |

The ordered fault queue retains the simple single-fault API. The effect sink
records each attempt separately from its deduplicated records. Synchronization
uses messages, monitors, telemetry, and actual timeout responses, not sleeps.

## Open contracts

- `SYSTEM-TOPOLOGY-01` and `SYSTEM-TOPOLOGY-02` remain enabled failing probes.
  A target accepted by a live Controller does not survive its Runtime restart
  or full Jido restart. Agent checkpoint durability is checked separately.
- File returns raw OS errors. Persistence classifies an unclassified write
  error as indeterminate and stops the Agent. A failed temporary write does not
  currently produce the narrower `:rejected` classification.
- `SYSTEM-SUPERVISION-01`: immediate Jido replacement exhausts its parent's
  restart budget while a held old Task Supervisor retains its name. The probe
  releases the child and verifies cleanup before failing the recovery contract.
- `SYSTEM-BEDROCK-01`: the placeholder survives unassisted cluster shutdown.
- `SYSTEM-BEDROCK-02`: live coordinator/log replacement reaches a new layout,
  but the transaction system does not become ready. Runs observed Distributor
  `startup_sweep_failed` / `already_started`; the 2026-09-14 coordinator run
  instead reported `sequencer_unavailable` / `wrong_epoch`. Fixture-assisted
  full restart is a separate checkpoint recovery control.
- `SYSTEM-TOPOLOGY-03`: three owned members survive control-tree failure during
  cleanup of a partial accepted update. The test removes them after collecting
  the ownership evidence.
- `SYSTEM-CLUSTER-01`: separate local registries permit two cluster owners.
  The approved core DIST-03 skip is unchanged.
- `SYSTEM-BUS-01`: durable input can be replayed during Agent initialization.
  Its synchronous Agent call competes with Plugin readiness, and startup can
  time out. ETS, File and SQLite reproduced this in the full normal run;
  focused ETS passed. This remains a timing-sensitive probe, not a claimed fix.
- Shared-Bus replacement readiness also timed out once on ETS in the
  2026-09-14 local run. The failed component was not captured; this is not
  evidence of an ETS adapter defect.
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
- New durable target APIs and storage guarantees are not added by this test
  work. Service prerequisites must fail explicitly, not select a fake adapter
  or silently skip a scenario.

## Verification

| Check | Result |
| --- | --- |
| `mix quality`, 2026-09-14 | Format, warnings-as-errors compilation, configured Credo checks and Dialyzer pass; 1104 core tests pass |
| `mix test.system`, 2026-09-14, seed 0 | 101/113 pass; nine Topology/supervision/ownership failures, two durable Bus startup timeouts on File and SQLite, and one shared-Bus replacement readiness timeout on ETS |
| `mix test.services`, 2026-09-14, seed 0, explicit Redis binary | 76/86 pass; six Topology target failures, three Bedrock replacement/shutdown failures and one strict-startup failure. The shared-Redis partition passes |
| Focused sustained partition probes | Two local peer tests pass with held Turn and late spawn; shared-Redis stale-write test passes with real CAS |
| `mix test.all --cover`, 2026-09-13, before the S3 adapter commit | 1991/2003 pass, 1 skipped, 87 excluded; 12 named system failures, 94.1% coverage. All 87 service statuses were `excluded` with an invalid Redis executable in the environment. This full command has not been rerun after the S3 commit |
| Full MinIO profile, 2026-09-14, seed 0 | 26/29 pass: two S3 Topology target failures and one Bedrock cold-rebuild readiness failure. Native upload also reports two `Jason.EncodeError` results; the binary control uploads two real snapshots. The owned bucket and objects were removed, and the dedicated server stopped |
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
block their later checks, and several runtime probes deliberately retain failed
contracts. Durable Topology target records, acceptance/CAS semantics, deletion,
restore/version rules and exclusive cluster authority remain core design work.
No new public API or guarantee was invented to make those probes green.

The local simplification pass kept the shared scenario design. It clarified the
Flow projection name and preserves the original model failure artifact before
reduction. No independent review was run: subagents were prohibited.
Code review: skipped (ce-code-review unavailable) — its independent review
workflow requires subagents; the final local diff scan is not that review.
