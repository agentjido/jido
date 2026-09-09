> Approved seam alignment. Dependent owner-seam follow-up remains open.

# Errors and public contracts alignment

## Status

- Design reviewed and approved: 2026-09-09.
- Code base: error-contract alignment commit `3e504be6` on branch `v3-spike`.
- Approved prerequisite: [00 Overview](../00_overview/alignment.md).
- Narrow pending prerequisite: [90 Package boundaries](../90_package-boundaries/alignment.md)
  for package ownership only.
- Alignment state: `Approved; foundational implementation complete`.

The review-status table in `docs/design/README.md` is the source of truth for
document approval.

## Audit result

The original draft was not safe to implement as written. It proposed two
classes that did not represent stable failure kinds, a large code list without
implemented owners, a projection v2 without a consumer, and public persistence
changes before seams 07 and 08 had set their lifecycle policy.

This alignment uses current code as the source of evidence. It makes only the
foundational changes that do not take policy from another owner.

## Retained baseline

- Keep Splode and the current class order.
- Keep `ValidationError`, `ExecutionError`, `RoutingError`, `TimeoutError`,
  `CompensationError`, and `InternalError`.
- Keep returned application and adjacent-package errors exact.
- Keep tagged and bang Agent APIs on one error path.
- Keep current persistence adapter controls and public persistence results.
- Keep current Agent Server and Jido lifecycle controls.
- Keep exact v1 `to_map/1` keys, arbitrary-term defense, bounds, redaction,
  UTF-8 safety, and JSON safety.
- Keep Agent portability checks from approved seam 01.
- Keep full persistence-record validation as defense in depth.

## Canonical evidence

### Error and projection

- `lib/jido/error.ex` defines five Splode classes and six public Jido error
  structs.
- `Jido.Error.stable_codes/0` now publishes the closed Jido-owned registry.
- `Jido.Error.code/1` reads only a registered Jido code.
- `Jido.Error.to_map/1` still returns only `type`, `message`, `details`, and
  `retryable?` at the top level.
- Error transport tests prove depth, item, string, redaction, stacktrace,
  UTF-8, and JSON rules.

### Callback boundaries

- `Jido.Agent.Command.Runner` preserves returned callback errors. It now
  contains `handle_signal/2` raise, throw, and exit faults.
- `Jido.Agent` preserves checkpoint and restore callback error reasons. It now
  converts invalid output and callback faults with Agent codes.
- `Jido.Plugin` preserves callback error reasons. It now codes invalid callback
  output and raise, throw, and exit faults.
- `Jido.AgentServer` codes Plugin admission and Directive task loss and limits.
- `Jido.AgentServer.ExecutionAdapter` codes invalid results, callback faults,
  process loss, and operation limits. It preserves an exact Exec callback
  `{:error, reason}`.
- `Jido.Persistence` preserves adapter error reasons. It now codes invalid
  adapter replies and raise, throw, and exit faults.

### Portability

- `Jido.Agent.State` validates complete Agent state, including Plugin-owned
  keys, before acceptance.
- `Jido.Agent` validates checkpoint output and restore input.
- `Jido.Persistence` validates the complete record before encode and after
  decode.
- `Jido.PortableTerm` rejects all six prohibited term classes. It now bounds
  paths to 20 segments and bounds each printable segment to 64 bytes.

### Current protocol controls and shaped values

- `Jido.Persistence.Adapter` documents byte values and the `:not_found`,
  `:conflict`, and `:indeterminate` meanings.
- Agent Server specs and tests require OTP results, cancellation atoms,
  readiness controls, debug controls, PID lookup, Registry names, and
  inspection maps.
- Jido instance specs and tests require OTP starts, lifecycle controls, PID
  lookup, `{id, pid}` lists, counts, and Map-like parent lookup.
- The target design now contains one consolidated failure-position,
  raw-control, and shaped-value inventory.

## Gap register

| Gap | Requirement | Audit finding | Alignment disposition | State |
| --- | --- | --- | --- | --- |
| `ERR-GAP-001` | `ERR-REQ-001` to `005` | Five classes already cover the failure kinds. Persistence and runtime classes would duplicate operation areas. | Keep five classes and six errors. Keep compensation compatibility. | `Aligned` |
| `ERR-GAP-002` | `ERR-REQ-003` | There was no stable Jido code registry. | Add the exact 13-code registry and `Error.code/1`. | `Aligned` |
| `ERR-GAP-003` | `ERR-REQ-006` to `010` | Conversion differed across callbacks. Returned application errors were already a public `term()` contract. | Apply the narrow matrix. Preserve returned reasons. Code only Jido-owned conversions. | `Aligned` for foundational callbacks |
| `ERR-GAP-004` | `ERR-REQ-011` | Some broad runtime containment can also catch a framework fault. The operation owner must identify each invariant. | Keep the OTP invariant rule. Defer each invariant classification to its runtime owner. | `Owner-deferred` to 08 and 10 |
| `ERR-GAP-005` | `ERR-REQ-012` and `013` | Persistence controls remain raw. Indeterminate Server writes already remove authority. | Register current controls and preserve them. Do not add a new error class. | `Proven` current rule; migration deferred to 07 and 08 |
| `ERR-GAP-006` | `ERR-REQ-014` | Plugin and Exec operation limits existed without stable codes. No persistence operation limit exists. | Add Plugin and Exec timeout codes. Do not invent a persistence limit. | `Aligned`; persistence policy deferred to 07 |
| `ERR-GAP-007` | `ERR-REQ-015` and `016` | The first draft named functions that do not exist and omitted many live controls. | Replace it with the code-based registry in the design. | `Aligned` |
| `ERR-GAP-008` | `ERR-REQ-017` to `019` | Exact v1 is safe and tested. No v2 consumer exists. | Keep exact v1 and retire the v2 requirement ID. | `Aligned` |
| `ERR-GAP-009` | `ERR-REQ-020` and `021` | Public value forms were spread across module docs and specs. | Add one grouped failure and shaped-value inventory. | `Aligned` |
| `ERR-GAP-010` | `ERR-REQ-022` to `024` | Seam 01 added early checks, but path segments were not all bounded. Persistence tests covered too few load cases. | Bound root and nested segments. Test all prohibited terms at Agent and persistence boundaries. | `Aligned` for current accepted values |
| `ERR-GAP-011` | All | No focused matrix linked codes, projection, callback faults, task loss, limits, and portability. | Add focused contract assertions and run the full non-research suite. | `Aligned` |

## Acceptance matrix

| Requirement | Evidence | State |
| --- | --- | --- |
| `ERR-REQ-001` to `005` | Error definitions, composition tests, and compensation tests | `Proven` |
| `ERR-REQ-006` and `007` | Public inventory and existing tagged/bang Agent tests | `Proven` for current converted APIs |
| `ERR-REQ-008` to `010` | Agent, Plugin, Persistence, and Exec callback tests | `Proven` |
| `ERR-REQ-011` | Existing Server crash-policy tests and the owner deferral | `Proven` as a rule; per-invariant audit is owner work |
| `ERR-REQ-012` and `013` | Persistence result tests and indeterminate-write tests | `Proven` |
| `ERR-REQ-014` | Plugin and Exec timeout code tests | `Proven` for current owned limits |
| `ERR-REQ-015` and `016` | Protocol registry, current specs, and public API tests | `Proven` |
| `ERR-REQ-017` and `018` | Exact-key and transport tests | `Proven` |
| `ERR-REQ-019` | No consumer requires v2 | `Retired` |
| `ERR-REQ-020` and `021` | Consolidated public inventory | `Proven` at seam level; field detail stays with value owners |
| `ERR-REQ-022` to `024` | Agent portability tests and standard persistence save/load tests | `Proven` for current state, checkpoint, and record boundaries |

## Completed alignment work

### Taxonomy and codes

- Challenged the proposed seven-class design.
- Kept the five implemented Splode classes.
- Added a typed, ordered code registry.
- Added `Jido.Error.code/1` without changing error structs.

### Boundary normalization

- Preserved callback-returned application errors and composed errors.
- Added codes to existing invalid-result and callback-fault conversions.
- Contained Agent `handle_signal/2` callback faults.
- Added codes for owned Plugin and Exec task loss and limits.
- Kept persistence and lifecycle controls compatible.

### Projection and values

- Proved the exact v1 top-level shape.
- Removed the unsupported v2 target.
- Replaced the incomplete protocol registry.
- Added the consolidated public result and value inventory.

### Portability

- Retained approved early Agent checks.
- Bounded root and nested path segments.
- Added persistence load defense tests for every prohibited term class.

## Migration phases and gates

### Phase 1 — Foundational alignment

- State: complete.
- Result: stable conversion codes, callback containment, exact v1 projection,
  bounded portability paths, and consolidated inventories.
- Gate: full package and quality checks pass.

### Phase 2 — Operation-owner migrations

- State: deferred to seams 05, 07, 08, and 09.
- Result: an owner can add a code or replace a registered control only after it
  defines the operation policy and proves compatibility.
- Gate: owner requirements, public tests, and a registry update are approved
  together.

### Phase 3 — Optional projection change

- State: no work planned.
- Result: keep exact v1.
- Gate: seam 13 names a consumer that cannot use v1 and supplies a migration
  test before it proposes a new projection.

## Compatibility rules

| Area | Rule |
| --- | --- |
| Error classes | Do not add persistence or runtime classes without a failure-kind case that the five classes cannot express. |
| Compensation | Keep `CompensationError` until `jido_action` has an approved and tested replacement. |
| Stable codes | Add codes only at Jido-owned conversions. Never reuse a code. Do not match messages. |
| Returned errors | Preserve declared callback `{:error, reason}` results exactly. |
| Persistence | Keep adapter and current public control reasons until seams 07 and 08 approve a migration. |
| Agent Server and instance | Keep raw lifecycle, cancellation, overload, reentry, and inspection controls until their owner approves a migration. |
| Projection | Keep the exact v1 top-level keys. A new form needs a consumer and migration test. |
| Portable values | Keep early Agent checks and persistence defense in depth. A later durable-work owner must add its own acceptance check. |

## Assumptions, blockers, and owner dependencies

| ID | Type | Owner | Statement | Resolution |
| --- | --- | --- | --- | --- |
| `ERR-BLK-001` | `Resolved` | 00 Overview | Overview is approved. | No action. |
| `ERR-BLK-002` | `Assumption` | 90 Package boundaries | One package owns each public concept; Jido does not copy accepted adjacent errors. | Confirm when seam 90 is approved. |
| `ERR-BLK-003` | `Resolved` | 12 | Jido keeps Splode and core composition. | Recorded in `ERR-DEC-001` and `008`. |
| `ERR-BLK-004` | `Owner dependency` | 05, 07, 08, 09 | Final operation meanings can add owner codes or migrate registered controls. | Each owner updates the registry with tests when its design is approved. |
| `ERR-BLK-005` | `Owner dependency` | 07 and 08 | Confirmed and indeterminate write policy is not fully closed. | Define retry, restart, reload, and any operation limit in those seams. |
| `ERR-BLK-006` | `Resolved` | 13 Observability | No current projection-v2 consumer was found. | Keep v1. Reopen only with a named consumer. |
| `ERR-BLK-007` | `Resolved` | 01 Agent | Agent state and checkpoint acceptance points are implemented and approved. | No action for current Agent values. |
| `ERR-BLK-008` | `Assumption` | 03 and value owners | New identity fields enter errors only after their value types are approved. | Add only bounded owner-approved identifiers. |

Owner dependencies do not block this foundational alignment. They block only
a future change to the owner's operation contract.

## Dependent-seam updates

- Seam 03 now treats portability as available and keeps Agent Ref details with
  the identity owner.
- Seam 05 can use the stable Plugin callback codes. Its final Plugin state and
  lifecycle contract remains owner work.
- Seam 07 now records that adapter controls remain raw and that invalid replies
  and callback faults have Jido codes.
- Seam 08 and seam 09 now record current lifecycle controls as compatible
  owner-managed migrations.
- Seam 13 no longer depends on a speculative projection v2.
- Seam 90 can use the approved public inventory as evidence.

## Verification record

- Focused contract tests: 287 passed.
- Standard persistence portability tests: 5 passed and include all six
  prohibited term classes.
- Full non-research package tests: 1,102 passed and 310 excluded.
- `mix quality`: passed with formatting, warning-free compile, strict Credo,
  Dialyzer, and 1,110 tests passed with 1 excluded.

## Completion criteria

- [x] The retained baseline is explicit.
- [x] The gap register states retain, align, or owner-defer for each gap.
- [x] The five-class taxonomy and six error modules match code.
- [x] The stable code registry is implemented and tested.
- [x] The callback normalization matrix is implemented at current core
      conversion points.
- [x] The raw-control registry and shaped-value inventory match current APIs.
- [x] Exact v1 projection behavior is retained and tested.
- [x] Agent and persistence portability boundaries have focused evidence.
- [x] Dependent blockers have a specific resolution or owner deferral.
- [x] The user has approved or changed the `ERR-DEC` items.
