# System scenario record

The optional suites now use the current Agent and AgentServer APIs. Tests for
the removed Topology controller, remote child startup, and commit projection
were removed. The following records describe retained checks. Older Bedrock
results are historical evidence; those probes remain skipped.

## Added scenarios

| Area | Implementation | Evidence |
| --- | --- | --- |
| Repeated recovery | `support/scenarios/recovery.exs` | Two confirmation write failures, four effect attempts, one deduplicated record; passes on ETS, File, SQLite |
| Late storage request | `support/scenarios/recovery.exs` | Captured old revision rejected after replacement or tombstone; passes on ETS, File, SQLite |
| Cancellation and deadlines | `support/scenarios/execution.exs` | Pre-commit cancellation/Turn timeout cannot save a late result; queued cancellation/caller timeout cannot reverse an accepted commit; passes on ETS, File, SQLite |
| Disk faults | `runtime/file_storage_test.exs` | Real corrupt bytes, directory permission error, rename failure, physical delete failure; no in-memory substitutes |
| Restore boundaries | `support/scenarios/restoration.exs` | Explicit restore mode reject an unsupported Plugin record; a tombstone during a held read prevents activation |
| Independent state oracle | `support/turn_model.exs` | Mixed success, rejection, cancellation, timeout, conflict, deletion, restart, and uncertain writes; seeded generation and bounded failure reduction |
| Combined overload | `support/scenarios/overload.exs` | Caller timeout, full queue, rejected calls/cast, Bus replacement, and worker death; exact request and event accounting |
| Immediate supervisor replacement | `runtime/supervision_test.exs` | Held old child, bounded name-release wait, replacement tree and unchanged checkpoint; passes with local Jido fix |
| Redis storage faults | `services/redis_faults_test.exs` | Real SIGKILL/AOF restart and TCP proxy reply loss after Lua execution; both pass |
| PostgreSQL | `services/postgres_test.exs` | Real isolated Docker database; current shared Agent scenarios pass |
| Bedrock storage faults | `services/bedrock_faults_test.exs` | Paused; earlier Bedrock 0.7.2 runs passed restarts and coordinator/log replacement, while unassisted placeholder cleanup failed |
| Real trace export | `runtime/open_telemetry_test.exs` | Four SDK tests pass: exported parentage, exporter failure isolation, handler failure isolation, and paired overhead measurements |
| Metrics and logs | `runtime/observability_test.exs` | Public counters, host revision gauge, structured log identity and payload redaction |
| Signal journey | `runtime/signal_journey_test.exs` | JSON validation and explicit key conversion, Bus/Router, Action/Flow, commit, Directive, failed acknowledgement and replay; latest run passes, earlier `SYSTEM-BUS-01` timeout needs repeats |
| Peer reconstruction | `runtime/peers_test.exs` | Three actual BEAM SIGKILLs with required File restores, held-work interruption and witnessed node loss; passes |
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

## Verification after the API update

| Check | Result |
| --- | --- |
| Default discovery | 1,194 passed; no compiler warnings |
| `mix test.all --warnings-as-errors` | 1,589 passed, one existing skip |
| `mix test.authoring` | 72 passed |
| `mix test.bench` | Eight passed; 118 smoke workloads |
| `mix test.peer` | Three passed |
| `mix test.system` | 95 passed, one existing cluster ownership skip |
| `mix test.services` | 59 passed, 36 existing Bedrock skips |
| Owned local MinIO profile | 31 passed, one existing Bedrock snapshot skip |
| Format, compile, Credo, Dialyzer | Passed; no warnings |
| Load runner, 10 activations, two cycles | Passed with and without persistence |

No new skips were added. The removed tests used deleted Topology controller,
remote child startup, or commit projection contracts. The current runtime rejects
remote child startup; the example tests check that rejection.

## Open contracts

Cluster ownership and real Bedrock service probes retain their approved skips.
The Bedrock placeholder, strict startup, snapshot upload, and cold rebuild issues
remain recorded in [TODO.md](TODO.md). The passing tests do not establish these
contracts or exactly-once external effects.

The optional metrics test uses the public catalog for current AgentServer
counters and adds a host-defined revision gauge. The catalog excludes deleted
Agent and Topology events and has duration summaries only for real spans.
