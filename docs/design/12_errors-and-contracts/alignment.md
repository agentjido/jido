> Seam alignment plan. This document is pending approval.

# Errors and public contracts alignment

## Status

- Design reviewed: 2026-09-08. All documents in this seam are pending
  approval.
- Code reviewed: `027093e699f3370f63623d41a3d80af52b9c7420`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md) and
  [90 Package boundaries](../90_package-boundaries/alignment.md), both used as
  pending draft prerequisites.
- Alignment state: `Draft`.

The alignment state is execution status. It is not document approval.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): defines public errors, useful caller-level
  failures, explicit structs, tagged results, standard OTP values, and the
  Bright Line.
- [Overview design](../00_overview/design.md): assigns public error and
  protocol-exception detail to this seam through `OVR-REQ-052`,
  `OVR-REQ-053`, and `OVR-REQ-065`.
- [Package-boundary design](../90_package-boundaries/design.md): assigns one
  owner to each extension contract and requires public documentation,
  executable tests, and compatible migration.
- [Target design](design.md): defines the recommended error and public-contract
  target. It is pending approval.

### Canonical code

- `lib/jido/error.ex:1-107`: Jido uses Splode with five classes in the order
  invalid, execution, routing, timeout, and internal.
- `lib/jido/error.ex:113-318`: six public structs cover validation, execution,
  routing, timeout, compensation, and internal failures. Their fields can hold
  general terms and maps. There is no common `code` field or public error union.
- `lib/jido/error.ex:514-535,858-895`: `to_map/1` accepts any term and returns
  `type`, `message`, `details`, and `retryable?`. `type` is a derived atom.
- `lib/jido/agent/command/runner.ex:29-46,120-153,178-202`: direct execution
  contains some invalid results and routing faults, but returned errors pass
  through, raises remain exceptions, and throws or exits become raw tuples.
- `lib/jido/plugin.ex:67-102,438-460,705-795,962-978`: Plugin callback specs
  use `term()` errors. Wrappers contain many callback faults but preserve
  returned arbitrary errors.
- `lib/jido/agent_server.ex:158-418,668-785,1493-1594`: public calls use broad
  result types and raw lifecycle or cancellation controls. Persistence failures
  use `{:persistence_failed, reason}`.
- `lib/jido/persistence/adapter.ex:10-44`: the byte adapter uses fixed controls,
  including not found, conflict, and indeterminate results.
- `lib/jido/persistence.ex:59-150,284-371,386-430`: public persistence returns
  raw controls and tuples. Adapter faults use `ExecutionError`. Complete records
  get portability checks before save and after load.
- `lib/jido/portable_term.ex:1-24`: recursive validation rejects PIDs,
  references, ports, functions, and improper list tails. It does not report a
  path and does not reject non-byte-aligned bitstrings.
- `lib/jido/agent/state.ex:23-75`: Agent state validation uses the complete Zoi
  schema but does not call the portability check.
- `lib/jido/agent_server/options.ex:8-34`: the Server has Directive and
  readiness limits, but it has no persistence operation limit.
- `lib/jido/observe.ex:293-312` and `lib/jido/telemetry/agent.ex:163-185`:
  observation uses the current bounded projection and its derived type.

### Tests and examples

- `test/jido/error/normalization_test.exs:139-325`: tests the current derived
  type and retry behavior for Jido and adjacent package errors.
- `test/jido/error_transport_test.exs:28-153,242-255`: tests bounds, redaction,
  JSON encoding, and the exact four top-level projection keys.
- `test/jido/plugin/result_contract_test.exs:64-90` and
  `test/jido/plugin/validation_test.exs:241-275`: require returned raw Plugin
  failures to pass through and require raised, thrown, or exited faults to
  become `ExecutionError` in several wrappers.
- `test/jido/agent_server/public_api_test.exs:450-475` and
  `test/jido/agent_server/runtime_observability_test.exs:15-36`: require raw
  cancellation and debug controls.
- `test/jido/persistence/indeterminate_write_test.exs:35-93`: proves that an
  indeterminate write stops the current Server before later Action work. It
  expects the current `persistence_failed` public result.
- `test/jido/persistence/checkpoint_portability_test.exs:1-49`: research tests
  prove persistence-time rejection for nested PIDs and improper lists. They do
  not prove rejection before direct or live candidate acceptance.

## Retained baseline

- Keep Splode as the error framework.
- Keep the current validation, execution, routing, timeout, compensation, and
  internal errors until each staged change has replacement proof.
- Keep tagged and bang construction APIs on one error path.
- Keep adjacent `jido_action` and `jido_signal` error ownership.
- Keep the current bounded projection, redaction, UTF-8 safety, JSON encoding,
  and retry hints during the projection migration.
- Keep adapter controls inside the documented adapter protocol.
- Keep Agent Server write-authority loss after an indeterminate write.
- Keep recursive persistence-record checks as defense in depth.
- Keep documented Map-like and OTP control results.
- Keep current PID, generated-name, persistence-selection, and inspection APIs.

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `ERR-GAP-001` | `ERR-REQ-001` to `ERR-REQ-005` | `lib/jido/error.ex:1-318` | Persistence and runtime classes are absent. Compensation remains in core. Fields are open and there is no union type. | `Change` with compatibility for compensation |
| `ERR-GAP-002` | `ERR-REQ-003` | `lib/jido/error.ex:484-499,858-895` | Derived types exist, but stable owner codes do not. | `Change` |
| `ERR-GAP-003` | `ERR-REQ-006` to `ERR-REQ-010` | Runner, Plugin, Persistence, and Agent Server evidence above | Public errors can be exceptions, atoms, tuples, maps, or defined errors. Normalization differs by boundary. | `Change` through staged boundary conversion |
| `ERR-GAP-004` | `ERR-REQ-011` | `lib/jido/agent_server.ex:1285-1322` | Preparation faults exit, but code does not clearly separate application faults from Jido invariant faults. | `Change` after owner fault classification |
| `ERR-GAP-005` | `ERR-REQ-012` and `ERR-REQ-013` | `lib/jido/persistence.ex:59-150,386-430`; `lib/jido/agent_server.ex:1493-1594` | Adapter controls remain raw in public persistence. Agent Server adds `persistence_failed`. Only uncertain failures always remove authority. | `Change`; exact write policy stays with seams 07 and 08 |
| `ERR-GAP-006` | `ERR-REQ-014` | `lib/jido/agent_server/options.ex:8-34` | Some operation limits exist. Caller waits and operation limits can still share raw timeout values. No persistence limit exists. | `Change`; do not add a persistence limit without seam-07 and seam-08 rules |
| `ERR-GAP-007` | `ERR-REQ-015` and `ERR-REQ-016` | Public Agent Server and Persistence APIs | Current raw controls exceed the target registry. Some are intentional test contracts. | `Change` with a per-boundary compatibility register |
| `ERR-GAP-008` | `ERR-REQ-017` to `ERR-REQ-019` | `lib/jido/error.ex:514-535`; transport tests | Projection is safely bounded, but it has no class or code and exposes general details. Exact keys are a tested contract. | `Change` through projection versions |
| `ERR-GAP-009` | `ERR-REQ-020` and `ERR-REQ-021` | Public specs across Agent, Plugin, Persistence, and Agent Server | Structs, maps, tuples, atoms, PIDs, names, and keyword lists have no one owner and migration inventory. | `Change` through owner inventories; exact later-seam values are deferred |
| `ERR-GAP-010` | `ERR-REQ-022` to `ERR-REQ-024` | `lib/jido/portable_term.ex:1-24`; Agent state and Persistence evidence | The check is late, has no path, and permits non-byte-aligned bitstrings. | `Change`; retain record checks |
| `ERR-GAP-011` | All requirements | Current tests above | No table proves the taxonomy, codes, full normalization matrix, protocol registry, version-2 projection, or early path-aware portability. | `Change` |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the implementation plan later with `ce-plan` after the design is
approved.

### Phase 0 — Resolve prerequisites and seam decisions

- Requirements: all `ERR-REQ` identifiers.
- Required outcome: approved taxonomy, code policy, normalization matrix,
  protocol registry, projection migration, and portability boundary.
- Constraints: treat Overview and package-boundary contracts as assumptions
  until their review rows are approved.
- Compatibility: no runtime change.
- Verification: review all `ERR-DEC` items against the gap register.
- Exit criteria: the user approves or changes each seam decision, and operation
  owners confirm the meanings that they own.

### Phase 1 — Lock the public inventory

- Requirements: `ERR-REQ-002`, `ERR-REQ-003`, `ERR-REQ-015`, `ERR-REQ-016`,
  `ERR-REQ-020`, and `ERR-REQ-021`.
- Required outcome: one inventory for exported failure positions, shaped
  values, protocol controls, owners, and compatibility status.
- Constraints: do not define later-seam state machines or value fields here.
- Compatibility: every current raw result has a retain, convert, deprecate, or
  internal-only disposition.
- Verification: public docs and types match the inventory.
- Exit criteria: no exported result position has an unowned `term()` meaning.

### Phase 2 — Establish taxonomy and normalization

- Requirements: `ERR-REQ-001` through `ERR-REQ-014`.
- Required outcome: defined persistence and runtime errors, stable owner codes,
  and one tested boundary normalization matrix.
- Constraints: preserve adjacent package errors and distinguish application
  faults from Jido invariant faults.
- Compatibility: convert one public boundary at a time. Keep temporary adapters
  for documented raw results.
- Verification: table-driven result, callback-fault, timeout, task-down,
  persistence-control, bang/tagged, and invariant-exit tests.
- Exit criteria: each converted failure returns one defined composed error.

### Phase 3 — Add safe projection version 2

- Requirements: `ERR-REQ-017` through `ERR-REQ-019`.
- Required outcome: a bounded typed projection with stable class and code.
- Constraints: no raw details, state, payload, context, process handle, cause,
  or stacktrace in version 2.
- Compatibility: keep the exact version-1 keys until seam 13 and external
  consumers have replacement proof.
- Verification: bounds, redaction, field allowlist, JSON, low-cardinality,
  Telemetry, log, and transport tests for both versions.
- Exit criteria: consumers can select version 2 without changing execution.

### Phase 4 — Enforce portable-value acceptance

- Requirements: `ERR-REQ-022` through `ERR-REQ-024`.
- Required outcome: path-aware checks at Agent state, Plugin state, checkpoint,
  durable-work, and persistence record boundaries.
- Constraints: each value owner decides when its value becomes valid. The
  persistence check remains defense in depth.
- Compatibility: identify current state schemas that accept runtime terms before
  enforcement. Use a staged migration if stored or live data conflicts.
- Verification: direct, live, Plugin, checkpoint, durable-work, save, and load
  tests for every rejected term class and for nested valid values.
- Exit criteria: no accepted target value contains a prohibited term, and each
  rejection reports a bounded safe path.

### Phase 5 — Close release evidence

- Requirements: all approved `ERR-REQ` identifiers.
- Required outcome: public docs, types, examples, and ecosystem contracts use
  the approved error and value rules.
- Compatibility: no current API is removed before its migration gate passes.
- Verification: package tests, public-only extension fixtures, and the V3
  compatibility matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` item for
  an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `ERR-REQ-001` to `ERR-REQ-005` | `lib/jido/error.ex:1-318` | Taxonomy, class order, closed fields, union type, adjacent composition, and compensation compatibility tests | `Conflict` |
| `ERR-REQ-006` and `ERR-REQ-007` | Agent construction uses defined errors; public runtime specs use `term()` | Exported result inventory plus tagged/bang parity tests | `Partial` |
| `ERR-REQ-008` to `ERR-REQ-010` | Runner and Plugin tests prove several different rules | Table-driven normalization across Agent, Plugin, Persistence, Agent Server, and instance boundaries | `Conflict` |
| `ERR-REQ-011` | `lib/jido/agent_server.ex:1285-1322` | Separate application-fault and deliberate invariant-fault cases | `Partial` |
| `ERR-REQ-012` and `ERR-REQ-013` | Adapter controls and indeterminate-stop tests | Public `PersistenceError` conversion and all write-result authority cases | `Partial` |
| `ERR-REQ-014` | Admission, readiness, and Directive limits exist | Caller-wait versus operation-limit matrix; persistence case only if owners approve it | `Partial` |
| `ERR-REQ-015` and `ERR-REQ-016` | Map-like, OTP, Agent Server, and adapter controls exist | Complete exported protocol registry and guard test | `Partial` |
| `ERR-REQ-017` and `ERR-REQ-018` | Current bounds, redaction, and JSON tests | Version-2 exact keys, allowlisted fields, excluded-data, and bounded-cardinality tests | `Partial` |
| `ERR-REQ-019` | Exact version-1 keys are tested | Dual-version tests and consumer migration evidence | `Proven` for current form; target migration is missing |
| `ERR-REQ-020` and `ERR-REQ-021` | Public values have mixed local documentation | Owner, purpose, validation, result, protocol reason, and compatibility inventory | `Partial` |
| `ERR-REQ-022` to `ERR-REQ-024` | Persistence record checks and research tests | Early path-aware matrix plus save/load defense-in-depth tests | `Partial` |

## Migration and compatibility

No deprecation or removal is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Error structs | Add persistence and runtime errors. Keep current structs and constructors until callers use stable codes. |
| Compensation | Keep `Jido.Error.CompensationError` until `jido_action` provides a proved public replacement and a separate deprecation is approved. |
| Raw failures | Convert by public boundary, not in one release-wide switch. Document the old and new result during each transition. |
| Stable codes | Add codes before callers stop using current type atoms or raw controls. Never reuse a retired code. |
| Projection | Keep the exact four-key version-1 map. Add version 2. Change any default only after seam-13 and external-consumer proof. |
| Arbitrary-term projection | Keep it as a named defensive compatibility path. Do not make arbitrary terms part of the final typed error contract. |
| Error fields | Stop adding raw state or callback values. Keep safe diagnostic causes outside the public projection during migration. |
| Provider controls | Keep controls in adapter callbacks. Convert them only at higher public Jido operation boundaries. |
| Agent Server controls | Keep current cancellation, hibernation, debug, startup, and overload results until each owner maps and migrates them. |
| Portable values | Audit existing live and stored data first. Add path-aware rejection at each owner boundary. Keep persistence validation. |
| Public values | Do not replace maps, tuples, atoms, PIDs, names, or keyword lists only to make them structs. The owner must justify and stage each change. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `ERR-BLK-001` | `Blocker` | 00 Overview | Overview requirements and decisions are pending approval. | Approve them or replace them with explicit seam-12 assumptions. |
| `ERR-BLK-002` | `Blocker` | 90 Package boundaries | Package ownership and compatibility decisions are pending approval. | Approve or change the package boundary. |
| `ERR-BLK-003` | `Assumption` | 12 Errors and contracts | Jido keeps Splode and a core composition. | Approve or change `ERR-DEC-001` and `ERR-DEC-008`. |
| `ERR-BLK-004` | `Blocker` | 01, 05, 07, 08, 09 | Operation owners have not confirmed the complete failure meanings and code list. | Each owner reviews its code and protocol entries before the registry closes. |
| `ERR-BLK-005` | `Blocker` | 07 Persistence, 08 Agent Server | The exact policy after confirmed and indeterminate persistence write failures is not final. | Define write authority, restart, reload, and any operation-limit behavior. |
| `ERR-BLK-006` | `Assumption` | 13 Observability | Existing consumers need the current four-key projection during migration. | Inventory consumers and prove version-2 adoption before a default switch. |
| `ERR-BLK-007` | `Blocker` | 01 Agent and 05 Plugins | The exact state-acceptance points and portable error path type are not approved. | Confirm boundaries and path encoding before enforcement. |
| `ERR-BLK-008` | `Assumption` | 03 Agent identity and other value owners | New identity fields can enter errors only after their types exist. | Add only owner-approved bounded identifiers. |

## Completion criteria

- [ ] The user has approved or changed each `ERR-DEC` item.
- [ ] Both prerequisite seams are approved, or this seam records replacement
      assumptions.
- [ ] Every exported failure position and protocol control has one owner,
      meaning, type, and compatibility disposition.
- [ ] Every approved `ERR-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains.
- [ ] Version-1 and version-2 projection contracts have passing consumer tests.
- [ ] Portable-value checks pass at every approved acceptance boundary and at
      persistence save and load.
- [ ] Public module docs and types match the approved contract.
- [ ] Dependent seam documents use the approved codes and protocol registry.
- [ ] After approval, `ce-plan` creates the formal implementation plan.
