> Seam alignment plan. This document is pending approval.

# Stable Agent identity alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `dc2b6844086a90f384102b2459f800a737f0cfdd` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md), and
  [01 Agent](../01_agent/alignment.md), all used as pending draft
  prerequisites.
- Alignment state: `Draft`.
- Approved decisions: None.

The alignment state is execution status. It is not document approval. This
file defines outcomes and gates. It is not an implementation plan.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): keeps explicit public values, direct calls,
  standard OTP composition, developer-owned architecture, and local core
  scope.
- [Overview design](../00_overview/design.md): recommends one Agent Ref for
  lookup, persistence, delivery, and placement. It separates PID from durable
  identity and keeps current PID APIs during migration.
- [Package-boundary design](../90_package-boundaries/design.md): assigns Agent
  identity to Jido core and keeps general transport and cluster policy outside
  core.
- [Errors and contracts design](../12_errors-and-contracts/design.md): requires
  one owner and validator for public shaped values. It permits `agent_ref` in
  safe errors only after the Ref type is approved.
- [Agent design](../01_agent/design.md): keeps a nonempty Agent ID in the Agent
  instance. It assigns Agent Ref, location, and live state version to later
  seams.
- [Target design](design.md): defines the recommended Ref contract.

### Canonical code

- `lib/jido/agent.ex:96-135,327-337`: an Agent instance has one nonempty
  string ID and no namespace or partition field.
- `lib/jido.ex:70-107,144-185`: `use Jido` has no namespace option. Generated
  lifecycle functions accept Agent values, modules, IDs, partitions, and PIDs.
- `lib/jido.ex:233-234,347-370,417-425`: Jido instances are atom-named local
  supervisors. Each owns a Registry. A partition can be any term.
- `lib/jido/agent_server.ex:295-310,2983-2986,3039`: registered Server names
  use Agent ID and optional partition in one selected Registry.
- `lib/jido/persistence.ex:59-160,248-307,330-383`: persistence keys and records
  use instance, Agent module, partition, and Agent ID. Load validates all four.
- `lib/jido/agent.ex:370-423,521-543`: the default checkpoint carries Agent
  module and ID. Restore rejects a module or ID mismatch.
- `lib/jido/agent_server/runtime_checkpoint.ex:8-50` and
  `lib/jido/runtime_store.ex:3-23`: local restart state uses instance-scoped
  ephemeral storage keyed by partition and ID.
- `lib/jido/agent_server/directive_runtime.ex:120-167,244-299` and
  `lib/jido/agent_server/parent_ref.ex:4-32`: relationships copy IDs and
  partitions, retain PIDs, and use private process references for live control.
- `lib/jido/agent/directive.ex:164-197` and
  `lib/jido/agent_server/child_placement.ex:8-39`: remote child creation keeps
  the requested node and requires the same named Jido instance on that node.
- `lib/jido/agent_server/state.ex:4-15`, `lib/jido/plugin/init.ex:4-19`, and
  `lib/jido/plugin/directive_context.ex:10-32`: runtime and Plugin values copy
  Jido instance, ID, and partition fields instead of one shared identity value.

### Tests and examples

- `test/jido/instance_test.exs:145-171,186-216`: persistence and local
  Registry tests separate equal IDs by partition. Current tests use atom
  partitions such as `:blue`.
- `test/jido/agent_server/startup_test.exs:96-117`: local lookup rejects a
  dead PID even while a suspended Registry still contains the entry.
- `test/jido/persistence/checkpoint_identity_test.exs:14-32`: record loading
  rejects a checkpoint with a different Agent ID.
- `test/jido/persistence/checkpoint_portability_test.exs:15-49`: portable
  checkpoint data round trips and nested PIDs or improper lists fail.
- `test/jido/agent_server/distributed_child_test.exs:11-117`: explicit remote
  placement keeps ID and partition. Lookup is local to the target node.
- `test/jido/agent_server/distributed_authority_test.exs:10-39`: compare-and-
  swap detects a stale write. The test for at most one live cluster owner is
  skipped.
- `examples/99_research/99_11_stable_reference/stable_reference.ex:25-46` and
  `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:21-80`:
  an application Ref can resolve local lookup on each call. Core namespace
  rebinding is not implemented.

## Retained baseline

- `ID-RB-001`: An Agent instance has a supported nonempty string ID.
- `ID-RB-002`: Equal IDs can exist in different Jido instances or
  partitions.
- `ID-RB-003`: Each Jido instance owns a unique-key local Registry.
- `ID-RB-004`: Local lookup resolves a current PID and rejects a dead PID.
- `ID-RB-005`: A Server process restart can retain the same Agent ID. Local
  runtime state stays scoped to one live Jido instance.
- `ID-RB-006`: Persistent restore can keep the same ID on another node.
- `ID-RB-007`: Persistence records and checkpoints validate their copied
  identity fields and portable contents.
- `ID-RB-008`: Compare-and-swap detects stale stored revisions. It does not
  prove exclusive live ownership across a cluster.
- `ID-RB-009`: Remote child placement keeps the child ID and partition.
- `ID-RB-010`: Spawn request generations are private activation-control
  identity. They are not stable Agent identity.
- `ID-RB-011`: ID-first, PID-first, generated-name, arbitrary partition, owned
  child, persistence adapter, and local lookup APIs are supported.

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `ID-GAP-001` | `ID-REQ-001` to `ID-REQ-013` | No `Jido.Agent.Ref`; research example has an application struct | Core has no Ref constructor, validator, equality rule, or portable map codec. | `Change` |
| `ID-GAP-002` | `ID-REQ-006`, `ID-REQ-015`, `ID-REQ-017` | Jido instance atom and module scope Registry and storage | No stable namespace can survive module replacement or bind one identity domain across instance lifetimes. | `Change`; seam 09 owns binding |
| `ID-GAP-003` | `ID-REQ-003`, `ID-REQ-016`, `ID-REQ-026` | Partition is `term()` and tests use `:blue` | The target Ref uses `nil` or a nonempty binary string. | `Change, staged` |
| `ID-GAP-004` | `ID-REQ-014`, `ID-REQ-018` | Agent, Registry, and RuntimeStore use separate ID and partition inputs | They do not start from one validated Ref. | `Change` |
| `ID-GAP-005` | `ID-REQ-019`, `ID-REQ-020`, `ID-REQ-027`, `ID-REQ-028` | Persistence key is `{instance, agent_module, partition, agent_id}` | Module and runtime instance are part of durable identity. No dual-read, collision, or rollback rule exists. | `Change, staged`; seam 07 owns record work |
| `ID-GAP-006` | `ID-REQ-021`, `ID-REQ-023`, `ID-REQ-024` | Parent and child delivery uses saved IDs and PIDs | Delivery does not carry one Ref and a changed PID can make a saved handle stale. | `Change`; seams 08 and 10 own resolution |
| `ID-GAP-007` | `ID-REQ-022` | Remote spawn carries node, Jido atom, ID, partition, parent PID, and request reference | Stable identity and requested location have no separate public values. | `Change`; do not change placement policy here |
| `ID-GAP-008` | `ID-REQ-025`, `ID-REQ-026` | Public ID, PID, generated-name, and term-partition APIs are active and tested | A direct replacement would break supported behavior. | `Retain` during additive migration |
| `ID-GAP-009` | All requirements | Current tests cover separate parts only | No acceptance set proves exact Ref preservation across all boundaries. | `Change evidence` |

## Dispositions of earlier analysis

| Earlier item | Disposition | Reason and owner |
| --- | --- | --- |
| Make stable namespace identity part of V3 | `Recommend` | The pending Overview already names Ref as a V3 target. Approval is still required. |
| Use `{namespace, partition, id}` | `Recommend` | It separates identity from code and location. `ID-DEC-001` is not approved. |
| Add a namespace option or callback now | `Defer detail` | Seam 09 owns configuration, binding, and duplicate namespace behavior. |
| Replace term partitions with strings at once | `Remove` | Atom and other term partitions are supported. Use a staged conversion. |
| Remove instance and Agent modules from persistence identity | `Change in stages` | Seam 07 must define old-key reads, collisions, rewrites, rollback, and release gates first. |
| Make each delivery resolve the current location | `Defer method` | This seam requires a Ref target. Seams 08 to 10 own local and transport resolution rules. |
| Put node or placement in the Ref | `Remove` | Location can change and is not identity. |
| Put Agent module or definition revision in the Ref | `Remove` | These describe code and restore compatibility, not logical identity. |
| Treat compare-and-swap as exclusive cluster ownership | `Remove` | Current revision checks detect conflicting writes only. Later authority work owns leases or fencing. |
| Add a cluster directory, cache lifetime, or stale-location retry here | `Defer` | Runtime topology owns location and retry policy. |
| Remove PID APIs when Ref exists | `Remove` | The pending compatibility contract keeps them until a proved owner-seam migration. |
| Use general Signal transport as the Agent directory | `Defer` | `jido_signal` owns transport, not Jido Agent location policy. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the implementation plan later, after the design is approved.

### Phase 0 — Resolve prerequisite and identity decisions

- Requirements: all `ID-REQ` identifiers.
- Required outcome: approved Ref tuple, exclusions, compatibility rule, and
  explicit owner assignments for namespace binding, storage, and topology.
- Constraints: do not select placement, transport, cluster directory, lease,
  or fencing behavior.
- Compatibility: no runtime or storage change.
- Verification: review each `ID-DEC` item and each blocker below.
- Exit criteria: prerequisite drafts are approved or replaced by explicit
  assumptions, and the user approves or changes each identity decision.

### Phase 1 — Establish the public Ref value

- Requirements: `ID-REQ-001` to `ID-REQ-013`.
- Required outcome: one validated, portable, exact-equality Ref and version-1
  map round trip.
- Constraints: keep the Agent value shape and do not add runtime data to Ref.
- Compatibility: additive public value only.
- Verification: construction, bang, validation, equality, unknown-key,
  unknown-version, and encoding round-trip contract tests.
- Exit criteria: each Ref value requirement has `Proven` evidence.

### Phase 2 — Bind Ref to Agent and local instance identity

- Requirements: `ID-REQ-014` to `ID-REQ-018`.
- Required outcome: Agent ID agreement, stable namespace binding, partition
  separation, and complete-Ref local lookup identity.
- Constraints: seam 09 owns configuration syntax and duplicate bindings.
- Compatibility: keep current instance, ID, PID, Registry, and partition APIs.
- Verification: equal-ID namespace and partition cases, process and instance
  restart, module rename, local lookup, and dead-handle tests.
- Exit criteria: one Ref keeps the same identity across all local lifetimes.

### Phase 3 — Align durable identity

- Requirements: `ID-REQ-019`, `ID-REQ-020`, `ID-REQ-027`, and `ID-REQ-028`.
- Required outcome: Ref-based durable identity with safe old-record reads,
  collision detection, rollback, and release gates.
- Constraints: seam 07 owns record and adapter-key formats. Definition revision
  and storage revision stay separate.
- Compatibility: no old record becomes unreachable before the migration gate.
- Verification: legacy fixtures, namespace and partition collisions, module
  rename, record rewrite, mixed-version, and rollback tests.
- Exit criteria: all supported records have one documented identity path.

### Phase 4 — Preserve Ref at live consumer boundaries

- Requirements: `ID-REQ-021` to `ID-REQ-024`.
- Required outcome: delivery and placement carry the exact Ref while handles
  and requested locations stay separate.
- Constraints: seams 08 to 10 decide resolution, stale-location, transport,
  placement, and authority behavior.
- Compatibility: keep direct PID commands and owned-child APIs.
- Verification: PID replacement, node movement, stale handle, node disconnect,
  and exact Ref propagation tests.
- Exit criteria: no consumer uses PID, node, module, or activation as
  Agent identity.

### Phase 5 — Close compatibility and dependent evidence

- Requirements: all approved `ID-REQ` identifiers.
- Required outcome: public docs, types, examples, and dependent seam documents
  use one approved identity vocabulary and migration state.
- Compatibility: no supported API is removed without its approved gate.
- Verification: format, compile, focused tests, full package tests, research
  controls, and the compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` item for
  an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `ID-REQ-001` to `ID-REQ-013` | Application Ref example only | Core value, field validation, exact equality, errors, and version-1 map round trips | `Missing` |
| `ID-REQ-014` | Agent ID and checkpoint identity checks | Ref-to-Agent mismatch test at every binding boundary | `Partial` |
| `ID-REQ-015` and `ID-REQ-017` | Separate Jido instance Registries and storage keys | Stable namespace tests across instance restart and module rename | `Partial` |
| `ID-REQ-016` | Partitioned Registry and persistence tests | Ref equality and isolation for `nil` and binary partitions | `Partial` |
| `ID-REQ-018` | Registry lookup by ID and partition | Complete-Ref registration, lookup, replacement PID, and dead PID tests | `Partial` |
| `ID-REQ-019` and `ID-REQ-020` | Module-based persistence keys and validated record fields | Ref-key records with separate module and definition-revision fields | `Conflict` |
| `ID-REQ-021` | Parent and child structures copy ID and partition | Exact Ref delivery after PID replacement | `Missing` |
| `ID-REQ-022` to `ID-REQ-024` | Explicit remote node placement keeps ID and partition | Ref-preserving node move, stale location, and disconnect tests | `Partial` |
| `ID-REQ-025` and `ID-REQ-026` | Current APIs and atom-partition tests | Compatibility inventory and release gates beside Ref-first APIs | `Proven` |
| `ID-REQ-027` and `ID-REQ-028` | No migration path | Collision, legacy read, mixed-version, rewrite, rollback, and removal-gate tests | `Missing` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Agent ID | Keep the nonempty `agent.id`. A bound Ref must agree with it. |
| Public lifecycle | Keep current ID-first and PID-first functions. Add Ref-first paths before a later deprecation review. |
| PID and generated names | Keep them as documented runtime controls. Do not use them as durable identity. |
| Partitions | Keep current term-valued options. Require explicit conversion and collision checks before a value enters the binary-string Ref field. |
| Jido instances | Keep current atom and module names. Add namespace binding without making current names durable identity. |
| Persistence | Keep old records readable. Seam 07 must define dual-read order, collision failure, rewrite timing, rollback, and the final removal gate. |
| Checkpoints | Keep Agent module and definition data as restore data. Add the exact Ref only through the approved Agent and persistence format migration. |
| Relationships and delivery | Keep owned-child and direct PID behavior while Ref targets and handle refresh get proof. |
| Remote placement | Keep explicit node requests. Node stays separate from Ref. |
| Cluster authority | Current compare-and-swap remains conflict detection. This seam adds no exclusive-owner claim. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `ID-BLK-001` | `Blocker` | 00 Overview | Stable Ref, identity separation, and V3 compatibility requirements are pending approval. | Approve them or replace them with explicit identity assumptions. |
| `ID-BLK-002` | `Blocker` | 90 Package boundaries | Core identity ownership and the local-core boundary are pending approval. | Approve or change the package boundary. |
| `ID-BLK-003` | `Blocker` | 12 Errors and contracts | Public value, validation error, portable map, and `agent_ref` projection rules are pending approval. | Approve the value and error rules before public Ref release. |
| `ID-BLK-004` | `Blocker` | 01 Agent | Agent ID and definition-revision contracts are pending approval. | Confirm that Ref uses `agent.id` and excludes definition revision. |
| `ID-BLK-005` | `Blocker` | 09 Jido instance | Namespace assignment, local binding, duplicate handling, and module-rename configuration are not defined. | Approve the instance binding contract. |
| `ID-BLK-006` | `Blocker` | 03 Agent identity | Current partitions accept any term, but the target Ref field is binary or `nil`. | Approve conversion, collision, and transition rules. |
| `ID-BLK-007` | `Blocker` | 07 Persistence | Legacy key reads, collision behavior, rewrite, rollback, and removal gates are not defined. | Approve the persistence migration before key changes. |
| `ID-BLK-008` | `Assumption` | 08 Agent Server, 09 Jido instance, 10 Runtime topology | Ref-first paths can be additive while current PID and ID controls stay supported. | Confirm exact APIs and results in the owner seams. |
| `ID-BLK-009` | `Assumption` | 10 Runtime topology and later authority owner | Location discovery and exclusive write authority remain separate from Ref. | Define those contracts without changing the identity tuple. |

## Completion criteria

- [ ] The user has approved or changed each `ID-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `ID-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains in the acceptance matrix.
- [ ] Ref construction, validation, equality, and portable encoding have public
      contract tests.
- [ ] Namespace and partition isolation work across process, instance, module,
      and node changes.
- [ ] Persistence migration keeps old records reachable and has collision and
      rollback proof.
- [ ] Delivery and placement preserve the exact Ref while location and handles
      stay separate.
- [ ] Current ID, PID, generated-name, partition, owned-child, and persistence
      APIs remain supported until approved owner-seam gates complete.
- [ ] No cluster directory, transport policy, placement policy, lease, or
      fencing contract is decided in this seam.
- [ ] Dependent seam documents use the approved identity contract.
- [ ] After approval, the formal implementation plan is created separately.
