---
title: Jido.Persistence component
status: current
last-reviewed: 2026-11-13
---

# Jido.Persistence component

Purpose: Record stored-value, codec, checkpoint, inspection, and adapter boundaries.
Review result: The confirmed V3 persistence design is implemented locally.

## Contract and coverage

Persistence owns stored records, codecs, namespace manifests, and Store
operations. AgentServer owns live state, Turn admission, and the Agent record
commit point.

| Responsibility | Entry points and invariants | Coverage |
| --- | --- | --- |
| Facade | `snapshot/1,2`, `restore/1,2`, `upgrade/2,3`, `resolve_config/2`; `save_agent/2,3`, `load_agent/3,4`, `load_agent_with_revision/3,4`, `upgrade_agent/4,5`, `delete_agent/3,4`. Return result tuples; invalid public inputs become structured errors. | Public tests, AgentServer activation/durable callers, manual save/load traced. |
| Record | Namespaced partition/ID key, module check, format, revision, checkpoint, active/deleted state. Tombstones retain a fence against stale writes. | Encode/decode, mismatch, stale revision, deletion and recreation traced. |
| Profile and codec | One Store and codec per instance namespace. Term is default and loads declared release modules before safe decode; tagged JSON is opt-in. The namespace manifest pins codec and V3 layouts. | Config, codec, cross-BEAM Ref load, JSON File, and manifest mismatch tests. |
| Store | `open/1`, `read/2`, `compare_and_swap/4`, `delete/2`, and optional `scan/3`; adapter requires option validation, get, CAS, and delete. A condition is missing, exact bytes, or an adapter token. | Custom adapter, malformed result, strict option, delete, scan, conflict, and uncertain-write paths traced. |
| Snapshot and Checkpoint | Complete stored Agent definition and state, reference checks, module identity, explicit upgrade Action. Default and custom checkpoint paths differ. | Round-trip, changed code, invalid state, upgrade and forbidden directive paths traced. |
| Plugin conversion | Convert only the Plugin-owned state slice with a declared persistence facet. Custom Agent checkpoints can own an opaque format. | Plugin and checkpoint tests traced. |
| ContinuationStore | Internal Runic bridge for facts, batches, and join references. CAS index updates, bounded deltas, tail recovery, runtime registration and best-effort cleanup. | Durable AgentServer execution and continuation tests traced. |
| WakeStore | One-minute buckets, 64 shards, generation-aware active index, startup retry, and cleanup retry. Runtime recovery does not scan. | Recovery fault, cleanup race, cleanup retry, and durable wait tests traced. |
| Adapters | ETS, File, Mnesia, Redis, Ecto, S3, Bedrock, plus Ecto migration support. Each owns its atomic write and option contract. | All source and adapter tests read; local backends tested. External services have proof limits below. |

`Store` contains callback faults and checks result shape. A malformed or timed
out write can have an unknown outcome. Do not turn it into a safe retry.
Manual save is not a live Agent lease. Restore uses the saved definition;
upgrade is explicit and must preserve identity and return no directives.

Save options are instance, namespace, partition, reason, revision, and expected
revision. Load/delete select the stored identity and instance; upgrade also
accepts its Action context. Unknown or repeated facade options are rejected.
`server_turn` and open/create helpers are reserved for AgentServer. Snapshot
helpers delegate their options to the checkpoint/snapshot boundary. Store
configuration is an adapter declaration or a unique `[store: ..., codec: ...]`
profile. Agent runtime inheritance always selects that one instance profile.
Disabled storage is distinct from a store that returns not-found.

## Adapter boundaries

| Adapter | Important rule and limit |
| --- | --- |
| ETS | Supervised local table ownership. It is not durable across node loss. |
| File | Temporary write and rename under a local-node lock. No proof of power-loss durability or coordination between separate BEAM nodes sharing a directory. |
| Mnesia | Existing set table with key/value fields; transactional CAS. Rejects use inside an existing transaction. |
| Redis | Injected command function and prefix; Lua owns atomic comparison and update. The adapter has no automatic TTL. |
| Ecto | Repo, schema and repo options; write token separates equal-value writes. Writes reject an outer Repo transaction. PostgreSQL and SQLite support is conditional on dependencies. |
| S3 | Conditional object write with ETag token, checksum and size limit. Monitored worker and watchdog bound the adapter call. No hidden write retry. |
| Bedrock | Optional supported dependency versions and isolated call with no retry. Real service proof is paused in the current test profile. |

## Duplication and Elixir design

Keep Store, Record, Snapshot, and Checkpoint as separate internal owners.
They separate bytes and atomicity from Agent data and state conversion. A
single generic persistence callback would hide these distinctions. Adapter
option checks have similar syntax but different constraints; extraction is
useful only if it removes policy duplication without hiding backend rules.

ContinuationStore uses trusted runtime terms and differs from public portable
document decoding. Its term reads must not become an untrusted input decoder.
Keep join-reference digest and bounded-delta checks. Cleanup is best effort;
it does not provide transactional rollback for an external effect.

## Findings and decisions

- **F1 — Resolved.** Redis automatic TTL is not supported. Backend eviction
  remains an operator durability risk.
- **F2 — Deployment limit.** File rename and local locking do not establish
  shared-directory or power-loss guarantees. State the supported deployment
  model before adding locks or sync operations. No disk-failure test was run.
- **F3 — Retained boundary.** Continuation storage and Plugin checkpoint
  conversion have distinct contracts but require the host persistence
  lifecycle. Retain them within Persistence for now. Separate proof surfaces
  can make their guarantees clearer without adding public components.

No safe large source deletion was established. The adapter count reflects
different storage guarantees, rather than proof of excess abstraction.

## Checks and proof gaps

The second focused R5 command passed 675 tests, with three exclusions. It
included Persistence, durable AgentServer, Signal and Signal codec tests.
ETS, File, Mnesia and local SQLite paths have local test evidence. Injected
service responses do not prove deployment behavior. Redis, PostgreSQL, S3,
and Bedrock service checks were not run. Full CI stopped in Action build
tests; see [R5](../../components.md).

The broad `jido.persistence` contract overlaps durable AgentServer and Plugin
proof. This is an ownership gap, not evidence that the runtime behavior is
absent. Review completion does not certify crash recovery on every backend.

## Sources

- [Facade](../../lib/jido/persistence.ex)
- [Store](../../lib/jido/persistence/store.ex)
- [Record](../../lib/jido/persistence/record.ex)
- [Snapshot](../../lib/jido/persistence/snapshot.ex)
- [Checkpoint](../../lib/jido/persistence/checkpoint.ex)
- [Continuation store](../../lib/jido/persistence/continuation_store.ex)
- [Redis](../../lib/jido/persistence/redis.ex)
- [File](../../lib/jido/persistence/file.ex)
- [Tests](../../test/jido/persistence)
- [Obligations](../../test/contracts/jido/persistence.obligations.md)
