---
title: Jido.Persistence component
status: current
last-reviewed: 2026-11-19
---

# Jido.Persistence component

This record covers the top-level Persistence review for [#453](https://github.com/agentjido/jido/issues/453).
The review used [`6fdc009a1edd6261f3e26509fa2905bb9192faa5`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5)
from `release/v3`. All four checklist items have evidence. The findings below
describe that reviewed commit. The implementation and checks are in this
component's fix PR.

## Public surface

| Surface | Contract |
| --- | --- |
| `Jido.Persistence` | `snapshot/1,2` captures the complete portable Agent. `restore/1,2` uses the saved definition and validates the restored Agent. `upgrade/2,3` runs an explicit Action and requires the same identity and no Directives. These operations accept a context map. |
| Stored Agent operations | `save_agent/2,3`, `load_agent/3,4`, `load_agent_with_revision/3,4`, `upgrade_agent/4,5`, and `delete_agent/3,4` return operation-specific success values or error tuples. Identity options are instance, namespace, and partition. Save also accepts reason, revision, expected revision, Agent revision, and an optional durable Turn. Stored upgrade accepts Action context and explicit legacy module atoms. Unknown and duplicate options fail. |
| V3 records | One binary key encodes namespace, partition, and Agent ID. The record checks the Agent module separately. Active records carry a revision, Agent revision, saved definition version, checkpoint, and optional runtime data. Logical deletion writes a tombstone. A stale revision, tombstone, or failed read cannot authorize a replacement. |
| Configuration and codecs | `resolve_config/2` accepts a Store declaration, a profile, inheritance from a named instance, or disabled storage. One profile selects one Store and one codec. Term is the default and uses safe Agent decode with release module loading. Tagged JSON is opt-in. The namespace manifest pins the codec, record versions, and wake layout at instance startup. |
| `Jido.Persistence.Store` | `open/1` checks required callbacks and options. `read/2` returns bytes and the condition from the same read. CAS uses missing, exact bytes, or an opaque read token. The result preserves confirmed success, conflict, rejection, and indeterminate outcome. `delete/2` is a physical maintenance operation. Adapters can also implement maintenance `put/3` and paged `scan/4`. |
| Inspection | The inspect and export Mix tasks load configuration without starting the instance or Agents. They use Store reads and optional scan. Exact inspection has an explicit full mode. Export emits JSONL and has a separate sensitive-output option. The default disclosure gap is tracked below. |

[Facade](../../lib/jido/persistence.ex) · [Record](../../lib/jido/persistence/record.ex) ·
[Store](../../lib/jido/persistence/store.ex) · [Public API tests](../../test/jido/persistence/api_test.exs) ·
[Persistence obligations](../../test/contracts/jido/persistence.obligations.md)

## Callers and test evidence

| Caller | Contract checked |
| --- | --- |
| Instance, AgentServer, and addressed lifecycle | Instance startup opens the namespace manifest. AgentServer creates revision zero, uses revision-fenced writes, publishes the commit result, and stops stale work after an uncertain write. Address load discovers the stored module and checks ownership on activation. Address delete delegates to Persistence after the Instance checks local residency. |
| Agent and Plugin | Snapshot validation checks portable data and code references. The default checkpoint converts only the state of a Plugin with a paired persistence facet. A complete custom Agent callback supplies its own state format. Restore checks state, identity, and the saved definition version after conversion. |
| Direct Durable and AgentServer Flow runtime | The continuation store uses the shared Store and profile. It preserves a committed batch when its count update is lost. Status and result use the read-only path. Runtime repair uses keyed reads and CAS. |
| Instance wake recovery | The shared profile stores a generation-aware wake index and shards. Startup gates readiness on the recovery result. Cleanup and retry belong to the Instance wake process. |
| Tools and telemetry | Inspection checks stored values and writes JSON or JSONL. The Store span reports operation, adapter, and result status. Store telemetry tests check that metadata excludes keys, values, tokens, and options. |

[AgentServer lifecycle](../../lib/jido/agent_server/lifecycle.ex) ·
[Address lifecycle](../../test/jido/instance/address_test.exs) ·
[Indeterminate writes](../../test/jido/persistence/indeterminate_write_test.exs) ·
[Codec and inspection tests](../../test/jido/persistence/codec_config_test.exs) ·
[Durable API tests](../../test/jido/durable/api_test.exs) ·
[Wake tests](../../test/jido/instance/wake_test.exs)

## Code quality and Elixir design

Keep the shared adapter contract at the byte boundary. Adapters use the
backend's atomic operation or, for local File storage, a BEAM-local lock and
rename. Store calls remain synchronous. The caller owns the decision to
recover after an indeterminate result. The adapter owns backend-specific
options and limits. One generic adapter process would add a second owner for
operations that already have a backend-specific atomic boundary.

Keep `Store`, `Record`, and the codec contract distinct. They own byte
operations, stored value validation, and encoding respectively. Snapshot and
Checkpoint own conversion to and from saved Agent data. Keep the namespace
manifest above the byte Store. Store CAS and physical delete can share one
write-result handler. Address deletion can also remove its second read when it
binds the tombstone to the first condition. Existing keys, formats, and outcome
categories have tests.

Keep Persistence as one top-level component. Store and Agent checkpoint
guarantees can have distinct proof without a new public component.
Continuation, wake, Plugin conversion, and adapter code were checked where
their interfaces affect the shared contract. Detailed reviews of these
interfaces and their implementations remain separate work. AgentServer and
Instance retain live state, result publication, timers, and recovery policy.
Persistence owns the stored inputs to those decisions. The wake and
continuation paths use keyed reads independently of inspection scans.

[Reach layers](../../.reach.exs) · [Store conformance tests](../../test/jido/persistence/conformance/local_test.exs) ·
[Adapter matrix](../../guides/reference/persistence-adapter-matrix.md)

## Adapter boundaries

| Adapter | Important rule and limit |
| --- | --- |
| ETS | Supervised local table ownership. It is not durable across node loss. |
| File | Temporary write and rename under a local-node lock. No proof of power-loss durability or coordination between separate BEAM nodes sharing a directory. |
| Mnesia | Existing set table with key/value fields; transactional CAS. Rejects use inside an existing transaction. |
| Redis | Injected command function and prefix; Lua owns atomic comparison and update. The adapter has no automatic TTL. |
| Ecto | Repo, schema and repo options; write token separates equal-value writes. Writes reject an outer Repo transaction. PostgreSQL and SQLite support is conditional on dependencies. |
| S3 | Conditional object write with ETag token, checksum and size limit. Monitored worker and watchdog bound the adapter call. No hidden write retry. |

## Defects

| Severity | Finding | Acceptance check |
| --- | --- | --- |
| P2 | Tagged JSON can acknowledge a checkpoint that fails decode. The preload pass counts JSON wrapper depth against the logical value limit. [#462](https://github.com/agentjido/jido/issues/462) · [JSON codec](../../lib/jido/persistence/codec/json.ex#L214) | Check nested round trips at the supported limit. Reject excessive depth before CAS and retain a readable prior revision. |
| P2 | Default exact inspection and JSONL include stored Turn Signal data and context. [#463](https://github.com/agentjido/jido/issues/463) · [Inspector projection](../../lib/jido/persistence/inspector.ex#L187) | Check that default output keeps useful metadata and excludes saved application values. Check explicit sensitive output and execution shape projections. |
| P2 | Direct Agent writes can bypass an existing namespace codec pin. [#464](https://github.com/agentjido/jido/issues/464) · [Direct save](../../lib/jido/persistence.ex#L254) · [Manifest](../../lib/jido/persistence/namespace_manifest.ex#L17) | A conflicting profile fails before an Agent write, including when the Agent key is absent. Check offline matching profiles and define behavior when the manifest is absent. |
| P2 | Address deletion can discard the initial condition and tombstone a concurrently committed revision. [#465](https://github.com/agentjido/jido/issues/465) · [Address delete](../../lib/jido/persistence.ex#L596) | One read supplies both identity and condition. A concurrent write survives. Check tokens, repeated deletes, and the missing key contract. |
| P2 | Wake recovery reports success with an indexed shard missing or behind its index generation. [#466](https://github.com/agentjido/jido/issues/466) · [Wake reads](../../lib/jido/persistence/wake_store.ex#L180) | Return a structured recovery error and use the existing readiness retry. Accept a current or newer shard, including valid empty shards. |
| P2 | A decodable execution value with the wrong batch shape can make workflow recovery raise. [#467](https://github.com/agentjido/jido/issues/467) · [Continuation recovery](../../lib/jido/persistence/continuation_store.ex#L393) | Return an invalid checkpoint error for malformed committed and tail batches. Preserve valid tail recovery and read-only queries. |
| P3 | Store can accept malformed scan pages, records outside the prefix, and cursors that do not advance. [#468](https://github.com/agentjido/jido/issues/468) · [Store scan](../../lib/jido/persistence/store.ex#L121) | Reject invalid pages before export consumes them. Preserve optional scan and valid File pages with an advancing cursor, even if the page is empty. |

## Behavior-preserving cleanup

**P3.** Share callback protection and write-result normalization for Store
CAS and physical delete. Preserve the public functions, input checks, adapter
arguments, single callback invocation, outcome shapes, operation names in
errors and telemetry, and existing read and scan contracts. Run the Store and
indeterminate-write suites. [#469](https://github.com/agentjido/jido/issues/469) ·
[Write-result branches](../../lib/jido/persistence/store.ex#L229)

## Verification

### Fix verification

- Regression tests failed on the reviewed source and passed with the fixes.
  The focused run passed 276 tests with three exclusions. It covered the
  shared Store, Agent records, codecs, inspection, Durable, and wake recovery.
- A direct write now confirms a namespace manifest before its first Agent CAS.
  A competing startup or writer can establish the manifest first. The
  losing writer continues only when the winning profile matches. AgentServer
  uses the manifest confirmed at startup for Turn commits.
- Store CAS and delete pass the same outcome tests before and after the
  refactor. Address deletion uses the original read condition for both byte
  and token adapters.

### Review verification

- Seven temporary probes confirmed the defects in #462 through #468. The
  cleanup in #469 has direct source and existing test evidence.
- The focused Persistence, Durable, wake, and persistence telemetry run passed
  248 tests with three exclusions.
- The combined Persistence, Durable, wake, AgentServer, and telemetry run had
  311 passes, two failures, and three exclusions. The topology handoff test
  passed on rerun. The concurrent Address delivery test timed out again in a
  single-test run. Its cause remains open at the Instance and AgentServer
  boundary. [Baseline test](../../test/jido/agent_server/durable_activation_contract_test.exs#L490)
- The cross-BEAM persistence, Mnesia disk restart, Address lifecycle, and
  topology handoff selection passed all 44 tests.
- `MIX_ENV=test mix format --check-formatted` passed. The review used Elixir
  1.20.4 and Erlang/OTP 29.
- This review used local and injected backends. Redis, PostgreSQL, and S3
  service runs are separate evidence. File atomic rename and its local
  lock have no proof for separate BEAM nodes that share a directory or for
  recovery after power loss. ETS keeps data only while its BEAM stays up.

The [earlier component review](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/docs/components/persistence.md)
retains its R5 test results and prior adapter boundary decisions.
