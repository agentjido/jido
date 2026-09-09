> Seam alignment plan. This document is pending approval.

# Topology control-plane alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `a58cc285d6f906b69448b5e2a72dc21091b07b49` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [07 Persistence](../07_persistence/alignment.md),
  [08 Agent Server](../08_agent-server/alignment.md),
  [09 Jido instance](../09_jido-instance/alignment.md), and
  [10 Runtime topology](../10_runtime-topology/alignment.md). Authority and
  recovery also use [06 Commit and effects](../06_commit-and-effects/alignment.md).
- Alignment state: `Blocked` on pending prerequisites, package ownership,
  stable Ref, namespace, authority epochs, and commit-time fencing.
- Approved decisions: None.

The alignment state is execution status. It is not document approval. This
file defines outcomes and gates. It is not the formal implementation plan.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): Jido is a local Agent library. The developer
  owns network topology, cluster strategy, deployment, and operational policy.
- [Overview design](../00_overview/design.md): keeps static local Topology and
  separates identity, location, and write authority.
- [Package-boundary design](../90_package-boundaries/design.md): keeps static
  local Topology in core and assigns membership, placement, rebalance, recovery
  services, claims, leases, and fencing to focused integrations.
- [Errors design](../12_errors-and-contracts/design.md): requires validated
  public values, defined errors, and closed provider controls.
- [Agent design](../01_agent/design.md): keeps runtime handles outside Agent
  state and separates definition revision from state version.
- [Agent identity design](../03_agent-identity/design.md): proposes exact
  `{namespace, partition, id}` Ref identity and excludes node, lease, epoch,
  PID, and storage revision.
- [Plugin design](../05_plugins/design.md): limits a Topology facet to pure
  static contribution and grants it no live authority.
- [Commit design](../06_commit-and-effects/design.md): gives Agent Server the
  one live commit point and does not make ordinary Directives durable.
- [Persistence design](../07_persistence/design.md): keeps per-Agent records,
  gives no discovery or lease service, and does not provide multi-Agent atomic
  commit.
- [Agent Server design](../08_agent-server/design.md): owns one activation but
  does not bind namespace, resolve Ref, select placement, or grant cluster
  authority.
- [Jido instance design](../09_jido-instance/design.md): provides local Ref
  resolution only and no implicit remote forwarding.
- [Runtime-topology design](../10_runtime-topology/design.md): keeps local
  process ownership and explicit known-node children separate from desired
  state, discovery, placement, and authority.
- [Target design](design.md): defines the recommended optional control-plane
  contract.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido/topology.ex:1-14,20-40` | Topology is static authoring data for Agents, groups, Buses, relationships, composition, and startup policy. It has no membership, placement, authority, or epoch field. |
| `lib/jido/topology.ex:45-78` | One module is a combined Agent and Topology authoring host. It exposes authoring owner helpers, but those helpers have no runtime authority. |
| `lib/jido/topology.ex:82-108` | Construction and instantiation validate data and build a plan without starting a process. |
| `lib/jido/topology/instance.ex:1-15` | An instance contains only ID, definition, input, and local plan. |
| `lib/jido/topology/plan.ex:1-16,34-70` | A plan contains local Agents, resources, dependency layers, lookup data, and component counts. |
| `lib/jido/topology/plan.ex:155-180` | Plan member IDs derive from one topology instance ID. Resource and Agent locations are not selected. |
| `lib/jido/topology/codec.ex:1-17,40-85` | Codec version 2 stores static definitions. It excludes input, plans, state, PIDs, and runtime status. |
| `lib/jido/topology/controller.ex:1-24` | The Controller supports one static local target and explicitly excludes live updates, cluster placement, ownership transfer, and cluster policy. |
| `lib/jido/topology/controller.ex:43-70` | A Controller is an application-supervised local tree with task, resource, and runtime children. Startup returns before readiness. |
| `lib/jido/topology/controller.ex:73-107` | Public status, readiness, repair, and local handle lookup operate on one Controller. |
| `lib/jido/topology/controller/runtime.ex:13-31,184-205` | Runtime state stores one fixed instance. Repair requests repeat a pass against that instance. |
| `lib/jido/topology/controller/runtime.ex:207-325` | A pass uses dependency layers, bounded concurrency, readiness, degraded status, and automatic or manual retry. |
| `lib/jido/topology/controller/runtime.ex:347-427` | Activation uses local Jido lookup and metadata markers. These checks do not provide cross-node authority. |
| `lib/jido/topology/controller/activation.ex:8-35` | Member activation uses the public Agent Server path and waits for local readiness. |
| `lib/jido/topology/controller/activation.ex:39-56` | Persistent child restore uses the normal single-Agent persistence contract. |
| `lib/jido.ex:346-370,430-599` | A Jido instance supplies local services and local Agent lifecycle functions. It has no cluster directory or control-plane service. |
| `lib/jido/persistence.ex:59-160` | Persistence uses per-Agent records and CAS. It does not issue ownership grants or discover Agents. |

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/topology/controller_test.exs:9-37` | Invalid local repair policy has no activation effect. Fixed-target startup, duplicate local Controller identity, state retention, and cleanup work. |
| `test/jido/topology/controller_test.exs:115-168` | Local Agent repair and unrelated-Agent conflict protection work. |
| `test/jido/topology/controller_test.exs:213-245` | Readiness retry and local instance scoping work. |
| `test/jido/topology/controller_test.exs:251-340` | Child state restore, Bus repair, and Controller worker recovery work for the same supplied target. |
| `test/jido/agent_server/distributed_authority_test.exs:10-30` | Shared CAS detects a stale writer after another node commits. |
| `test/jido/agent_server/distributed_authority_test.exs:32-39` | Exclusive cluster ownership is skipped and not proved. |
| `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:21-58` | An application-level Ref can resolve local replacement and separate bindings. Core Ref and durable namespace are missing. |
| `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:60-80` | Durable namespace rebinding is skipped and not proved. |
| `test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:13-42` | Example code can compare Agent plan entries and validate a new target without live effects. |
| `test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:55-78` | Full Controller replacement can restore Agent state but replaces all PIDs. |
| `test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:80-97` | Live target growth is skipped and not implemented. |
| `guides/core-scope.md:53-101` | Public guidance limits repair to one existing target and marks leases, fencing, membership, placement, failover, and live updates as deferred. |
| `guides/deployment-and-shutdown.md:69-78` | Multi-node guidance assigns ownership, routing, fencing, and reconciliation to the application or an integration package. |

The removed gap report recorded 99 passing focused Topology tests and one
skipped live-update test on 2026-09-08. This historical result proves only the
local static contract. It does not prove a distributed target.

## Retained baseline

- `TOP-RB-001`: Module DSL, direct data, Builder, and Codec produce validated
  static Topology definitions.
- `TOP-RB-002`: Instantiation validates one input and builds one stable local
  plan without starting a process.
- `TOP-RB-003`: The combined authoring host exposes Agent and Topology helpers.
  An authoring helper is not live authority.
- `TOP-RB-004`: One application-supervised Controller owns one fixed local
  target and its repair timing.
- `TOP-RB-005`: Local activation uses bounded tasks, dependency order,
  readiness checks, and public Jido lifecycle functions.
- `TOP-RB-006`: Healthy owned local members keep their PIDs and state during a
  repair pass.
- `TOP-RB-007`: Normal Controller shutdown stops owned Agents in reverse
  dependency order. It does not stop unrelated conflicting Agents.
- `TOP-RB-008`: Persistent member restore uses independent single-Agent
  records. Topology has no durable desired-state or multi-record transaction.
- `TOP-RB-009`: Current explicit remote child placement requires a known node
  and has no discovery, fallback, failover, or exclusive-owner guarantee.
- `TOP-RB-010`: Core has no membership provider, distributed directory,
  placement policy, lease, epoch, fencing, handoff, or operator control plane.

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `TOP-GAP-001` | `TOP-REQ-001` to `TOP-REQ-005` | Topology and Controller code | Static local roles work. Distributed boundary documentation was mixed with an owner-Agent proposal. | `Retain` local roles; `Change` boundary text |
| `TOP-GAP-002` | `TOP-REQ-006` to `TOP-REQ-011` | No provider contract | Membership and discovery inputs do not exist. | `Missing`; external owner required |
| `TOP-GAP-003` | `TOP-REQ-012` to `TOP-REQ-018` | CAS conflict test; exclusive-owner test skipped | CAS detects one stale revision. There is no grant, epoch, expiry, or commit fence. | `Conflict` with any exclusive-owner claim; `Blocked` |
| `TOP-GAP-004` | `TOP-REQ-019` to `TOP-REQ-024` | Explicit known-node child only | No automatic placement, capacity, constraints, deterministic policy, or explanation exists. | `Missing`; keep library choice deferred |
| `TOP-GAP-005` | `TOP-REQ-025` to `TOP-REQ-033` | Persistent local restore and full Controller replacement | No durable operation state, fenced handoff, rollback, or automatic recovery exists. | `Missing`; `Blocked` on authority and persistence targets |
| `TOP-GAP-006` | `TOP-REQ-034` to `TOP-REQ-038` | Application Ref example only | Core Ref, namespace binding, distributed location record, and re-resolution contract do not exist. | `Missing`; `Blocked` on seams 03 and 09 |
| `TOP-GAP-007` | `TOP-REQ-039` to `TOP-REQ-044` | Deployment guidance only | No network-partition or stale-epoch runtime enforcement exists. | `Missing`; `Blocked` on authority mechanism |
| `TOP-GAP-008` | `TOP-REQ-045` to `TOP-REQ-048` | Local Controller status map | Local pass status exists. Distributed semantic events and state separation do not. | `Partial`; event schema deferred to seam 13 |
| `TOP-GAP-009` | `TOP-REQ-049` to `TOP-REQ-058` | Manual local `reconcile/2` only | No authenticated audit, preview, cordon, drain, move, rebalance, suspend, or resume contract exists. | `Missing`; product UI remains out of scope |
| `TOP-GAP-010` | `TOP-REQ-059` to `TOP-REQ-062` | Current public local APIs and old proposal | Compatibility is implemented. Error normalization is partial. Old owner-Agent runtime claims conflict with prerequisite boundaries. | `Retain` APIs; `Remove` implicit authority; `Defer` live update |

## Dispositions of superseded claims

| Superseded claim | Disposition | Reason and owner |
| --- | --- | --- |
| One module can be a combined Agent and Topology authoring host. | `Retain`. | Current code and authoring tests prove it. It remains static authoring. |
| `owner/0`, `new_agent/1`, and Topology `new/1` compatibility are implemented. | `Retain`. | These are public authoring helpers. They do not grant control-plane authority. |
| Add owner fields to Topology, Instance, and Plan. | `Defer`. | Distributed identity uses Agent Ref. No current control-plane need proves these core fields. |
| Encode an owner Agent in a new Topology Codec version. | `Defer`. | Current Codec stores static Topology data. A format change needs an approved data need and migration. |
| An included Topology must not start a second owner Agent. | `Replace`. | Current composition contributes one flattened static graph and starts no authoring owner Agent. |
| Store desired Topology input in a reserved owner Plugin state key. | `Remove from this target`. | Distributed desired placement belongs to the control-plane owner. Plugin state is not cluster consensus. |
| Add typed Topology Directives that commit desired state through an owner Turn. | `Remove from this target`. | Control-plane operations need durable multi-step operation semantics, not an ordinary transient Directive batch. |
| Put the local Controller under a Topology Plugin runtime. | `Remove`. | Seam 05 gives a Topology facet static authority only. Seam 10 keeps the Controller application-supervised. |
| Add `Jido.start_topology` and return an owner Agent PID. | `Defer`. | No approved startup contract requires it. The current Controller PID and readiness APIs remain supported. |
| Treat the owner Agent as the only live desired-state authority. | `Remove from distributed target`. | An Agent activation cannot provide membership consensus, placement policy, or stale-owner fencing. |
| Commit bootstrap desired state before the first child starts. | `Replace`. | Local static startup remains current behavior. Distributed startup must first have desired placement and a fenced authority grant. |
| Make the local Controller accept replaceable targets and state versions. | `Defer to a separate live-update design`. | Current repair is fixed-target. Distributed placement must not hide this missing local API. |
| Keep unchanged PIDs during live target growth or definition change. | `Retain as later acceptance intent`. | The skipped upgrade test specifies this outcome but does not prove it. |
| Define repair, resize, upgrade, rolling update, and rollback as distinct operations. | `Retain with changed ownership`. | Repair stays local. Move, rebalance, handoff, recovery, and rollback belong to the optional control plane. Live definition update remains separate. |
| Resolve definition revision to exact deployed code in this seam. | `Defer`. | Seams 01 and 08 own definition checks and loaded-code limits. Deployment owns artifact rollout. |
| Use local metadata markers as exclusive ownership. | `Reject`. | Markers protect one local Controller from unrelated local processes. They do not fence another node. |
| Treat persistence CAS as exclusive cluster ownership. | `Reject`. | Current CAS detects conflicting revisions after writes. It does not issue or renew authority. |
| Choose a specific distributed library. | `Reject`. | Membership, authority, storage, and transport providers remain separate and provider-neutral. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the implementation plan later, after the design is approved.

### Phase 0 — Resolve scope and prerequisite decisions

- Requirements: all `TOP-REQ` identifiers.
- Required outcome: approved package owner, local compatibility boundary,
  authority model, partition rule, and operator roles.
- Constraints: do not select a vendor or distributed library.
- Compatibility: no runtime change.
- Verification: review each `TOP-DEC` item and every blocker below.
- Exit criteria: prerequisite drafts are approved or replaced by explicit
  assumptions, and the user approves or changes each topology decision.

### Phase 1 — Lock the local component contract

- Requirements: `TOP-REQ-001` to `TOP-REQ-005`, `TOP-REQ-059`, and
  `TOP-REQ-060`.
- Required outcome: static authoring, planning, fixed-target local repair, and
  the external control-plane boundary have one clear contract.
- Constraints: keep current Controller APIs and application supervision.
- Compatibility: no removal or changed repair meaning.
- Verification: authoring, Codec, composition, Controller, readiness, repair,
  conflict, restore, and cleanup tests.
- Exit criteria: public docs contain no distributed claim for local behavior.

### Phase 2 — Establish identity and provider inputs

- Requirements: `TOP-REQ-006` to `TOP-REQ-011` and `TOP-REQ-034` to
  `TOP-REQ-038`.
- Required outcome: stable Ref, namespace, membership snapshots, desired
  placement, and location records have validated owner-specific boundaries.
- Constraints: membership cannot grant authority. Ref cannot contain location.
- Compatibility: add provider and Ref paths beside current ID, PID, and
  known-node APIs.
- Verification: generation, duplicate-node, stale-view, namespace, location
  replacement, and re-resolution tests.
- Exit criteria: each placement input has one owner and one accepted revision.

### Phase 3 — Establish enforceable authority

- Requirements: `TOP-REQ-012` to `TOP-REQ-018` and `TOP-REQ-039` to
  `TOP-REQ-044`.
- Required outcome: increasing epochs, commit-time stale-epoch rejection,
  optional lease expiry, and network-partition behavior have executable proof.
- Constraints: Registry presence, membership, and CAS conflict are not grants.
- Compatibility: deployments without fencing stay best-effort and make no
  exclusive claim.
- Verification: overlapping holder, lost renewal, delayed message, stale
  writer, partition, heal, and external-effect fence tests.
- Exit criteria: every lower epoch is rejected after a higher epoch exists.

### Phase 4 — Add placement, handoff, and recovery outcomes

- Requirements: `TOP-REQ-019` to `TOP-REQ-033`.
- Required outcome: deterministic placement and durable idempotent operations
  use public Jido activation and restore boundaries.
- Constraints: do not inspect or copy checkpoint contents. Do not call a local
  repair pass a handoff or update.
- Compatibility: current static Controller remains available.
- Verification: no-capacity, changed input, retry, partial activation,
  readiness failure, stale location, handoff, recovery, and rollback tests.
- Exit criteria: each operation has one final or resumable recorded result.

### Phase 5 — Add operation and observation contracts

- Requirements: `TOP-REQ-045` to `TOP-REQ-058` and `TOP-REQ-061`.
- Required outcome: bounded status, semantic events, authenticated audit, safe
  controls, preview, and defined errors.
- Constraints: observation and force actions have no authority bypass.
- Compatibility: keep local status and manual repair.
- Verification: event field, redaction, handler-failure, authorization, audit,
  preview, cordon, drain, move, suspend, and resume tests.
- Exit criteria: an operator can explain each decision without private state.

### Phase 6 — Close release evidence

- Requirements: all approved `TOP-REQ` identifiers.
- Required outcome: public docs, package boundary, failure matrix, provider
  conformance, and deployment claims agree.
- Compatibility: no supported core API is removed without a separate gate.
- Verification: format, compile, focused tests, full package tests,
  public-only integration fixture, network fault tests, and mixed-version
  rollback tests.
- Exit criteria: no approved requirement is `Missing`, `Conflict`, or
  `Blocked` in the acceptance matrix.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `TOP-REQ-001` | `lib/jido/topology.ex:82-108`; authoring and validation tests | Public contract inventory | `Proven` |
| `TOP-REQ-002` | `lib/jido/topology/controller.ex:81-90`; runtime fixed instance | Fixed-target regression test | `Proven` |
| `TOP-REQ-003` to `TOP-REQ-005` | Core scope and package design | Public-only external integration fixture | `Partial` |
| `TOP-REQ-006` to `TOP-REQ-011` | None | Membership provider contract and stale-view tests | `Missing` |
| `TOP-REQ-012` to `TOP-REQ-018` | CAS conflict only; exclusive-owner test skipped | Grant, epoch, expiry, stale-commit, and claim tests | `Conflict` |
| `TOP-REQ-019` to `TOP-REQ-024` | Explicit known-node child placement only | Constraint, capacity, deterministic choice, and unscheduled tests | `Missing` |
| `TOP-REQ-025` to `TOP-REQ-033` | Local restore and full replacement examples | Durable operation, fencing, readiness, retry, and rollback tests | `Missing` |
| `TOP-REQ-034` to `TOP-REQ-038` | Application-level Ref example | Core Ref, namespace, location, and re-resolution tests | `Missing` |
| `TOP-REQ-039` to `TOP-REQ-044` | Deployment guidance only | Network-partition and stale-epoch enforcement tests | `Missing` |
| `TOP-REQ-045` to `TOP-REQ-048` | Local Controller status only | Distributed event, status, redaction, and handler-failure tests | `Partial` |
| `TOP-REQ-049` to `TOP-REQ-058` | Manual local repair only | Authenticated audit and every operator-role test | `Missing` |
| `TOP-REQ-059` and `TOP-REQ-060` | Current Topology APIs and docs | Compatibility inventory and terminology guard | `Proven` |
| `TOP-REQ-061` | Current failures include atoms, tuples, and errors | Approved seam-12 mapping for each control-plane boundary | `Partial` |
| `TOP-REQ-062` | No owner Agent controls the current Controller | Public boundary and no-implicit-authority test | `Proven` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Static authoring | Keep DSL, direct values, Builder, Codec versions 1 and 2, composition, and authoring extensions. |
| Owner helpers | Keep `owner/0` and `new_agent/1` as current authoring compatibility. Do not give them implicit control-plane meaning. |
| Local Controller | Keep application supervision, fixed target, status, readiness, repair modes, and lookup functions. |
| Repair | Keep `reconcile/2` as same-target repair. Any update API needs separate approval and live-diff proof. |
| Agent lifecycle | Keep current ID, PID, partition, and explicit known-node functions while Ref-first paths are additive. |
| Persistence | Keep per-Agent records and current adapters. Add no control-plane record data to Agent checkpoints. |
| Best-effort placement | Permit deployment without fencing only when status and docs exclude exclusive ownership and safe failover claims. |
| Provider rollout | Version membership, authority, desired-placement, location, and operation records separately. Prove old-reader and rollback behavior. |
| Mixed versions | Do not enable automatic recovery until every active writer can enforce epochs. |
| Rollback | Disable new automatic operations first. Preserve authority records and fence values. Roll back provider and runtime support as one compatible unit. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `TOP-BLK-001` | `Blocker` | 00 Overview | Static Topology retention and distributed scope are pending approval. | Approve or change the Overview topology decision. |
| `TOP-BLK-002` | `Blocker` | 90 Package boundaries | The external control-plane owner and public integration boundary are pending. | Approve package placement before API design. |
| `TOP-BLK-003` | `Blocker` | 12 Errors and contracts | Provider controls, operation errors, and safe projections are not approved. | Approve result and error ownership. |
| `TOP-BLK-004` | `Blocker` | 03 Agent identity, 09 Jido instance | Core Ref and stable namespace are target designs only. | Implement and prove exact Ref binding and local resolution. |
| `TOP-BLK-005` | `Blocker` | 06 Commit, 07 Persistence, 08 Agent Server | No activation or commit boundary accepts and enforces an authority epoch. | Approve the narrow fencing contract and failure rule. |
| `TOP-BLK-006` | `Blocker` | 07 Persistence | Revision-zero records, tombstones, Ref keys, and all-write-error authority loss are not implemented. | Complete the approved durable lifecycle prerequisites. |
| `TOP-BLK-007` | `Blocker` | External authority owner | Grant source, epoch durability, optional lease clock model, renewal margin, and provider fault set are not selected. | Define and prove one provider contract before exclusive claims. |
| `TOP-BLK-008` | `Blocker` | External cluster owner | Membership source, node identity, generation, capacity units, and stale-view policy are not selected. | Define provider data and conformance tests. |
| `TOP-BLK-009` | `Blocker` | 11 Control plane | Partial handoff, retry, rollback, and operation-record retention policies are not approved. | Approve operation state and recovery semantics. |
| `TOP-BLK-010` | `Assumption` | 10 Runtime topology | Explicit known-node activation remains the lowest remote placement primitive. | Confirm or add one narrow public activation boundary. |
| `TOP-BLK-011` | `Assumption` | 13 Observability | Seam 13 will define exact event names and bounded field encodings. | Map the approved transition facts without adding authority. |
| `TOP-BLK-012` | `Blocker` | 11 Control plane | Live local target replacement is not implemented and is not part of this target. | Keep it deferred or approve a separate design pass. |
| `TOP-BLK-013` | `Resolved` | Design index owner | The main review table now lists the control-plane briefing, design, and alignment files. | Keep repository-wide link checks in the documentation gate. |

## Completion criteria

- [ ] The user has approved or changed every `TOP-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `TOP-REQ` item has `Proven` evidence.
- [ ] No approved requirement has a `Missing`, `Conflict`, or `Blocked` state.
- [ ] Current static Topology and fixed-target local repair remain supported.
- [ ] Membership, location, identity, and authority have separate values and
      provider contracts.
- [ ] A stale authority epoch cannot commit Agent state or a fenced external
      effect.
- [ ] Handoff, recovery, retry, rollback, and network partition tests pass.
- [ ] Operator actions are authenticated, audited, previewable, and fenced.
- [ ] Distributed claims use only public Jido contracts and one tested package
      set.
- [ ] Dependent seam documents and the main design index use the approved
      three-file contract.
- [ ] A separate formal implementation plan is created only after approval.
