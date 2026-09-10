> Implemented seam alignment. This document records the approved error
> contract, its package-boundary revalidation, and current evidence.

# Errors and public contracts alignment

## Status

- Error contract approved: 2026-09-09.
- Package and owner-seam revalidation completed: 2026-09-10.
- Alignment state: `Implemented`.
- Compatibility state: additive. Existing error structs, error codes, returned
  callback errors, raw protocol controls, projection version 1, and public
  success shapes stay supported.
- Follow-on work: seam 13 owns observation use. Seam 99 owns the final public
  inventory and delivery gate.

## Revalidation result

The package boundary and owner seams keep the approved five-class taxonomy.
They add no need for a persistence class, runtime class, or projection version
2.

The completed Agent, Plugin, Persistence, Agent Server, and Jido instance seams
added public owner results. Source already emitted eight codes after the first
13-code registry was created. Five were registered by their owner seams. This
revalidation registers the other three existing codes:

| Existing code | Owner | Trigger |
| --- | --- | --- |
| `:invalid_checkpoint` | Agent | A versioned or custom checkpoint envelope fails its owned contract. |
| `:definition_mismatch` | Agent and Persistence | A definition or stored revision does not match the loaded Agent definition. |
| `:plugin_state_owner_violation` | Agent Plugin | An executable changes a Plugin-owned state key. |

The names and failure locations do not change. `Jido.Error.code/1` now reads
them. The closed registry contains 21 codes.

## Selected contract

Jido applies this normalization matrix:

| Failure source | Result | Compatibility rule |
| --- | --- | --- |
| Declared callback returns `{:error, reason}` | Preserve the exact reason. | Application and adjacent-package ownership stays intact. |
| Invalid callback output | Owner validation or execution error with its invalid-result code. | The owner selects the class. |
| Callback raise, throw, or exit | Owner `ExecutionError` with its callback-failed code. | Diagnostic details stay bounded at transport. |
| Owned task exit | Owner `ExecutionError` with its task-failed code. | Monitor envelopes do not become public results. |
| Owned operation limit | Owner `TimeoutError` with its timeout code. | Caller wait timeout stays an OTP control. |
| Persistence adapter control | Preserve the documented adapter reason. | Persistence owns any later migration. |
| Broken internal invariant | OTP process exit. | Do not report it as an application rejection. |

`Jido.Error.to_map/1` returns only `type`, `message`, `details`, and
`retryable?`. It accepts arbitrary failure terms for defensive reporting. The
projection is bounded, sanitized, UTF-8 safe, and JSON safe. It can still
contain application data in allowed detail fields, so the caller must review
details before exposing them to an untrusted user.

Portable complete Agent state, checkpoint data, and persistence records
reject every PID, port, reference, function, improper list, and
non-byte-aligned bitstring. A rejection has `:non_portable_term` and a bounded
path that does not copy the rejected value.

## Package-boundary revalidation

| Value group | Public contract | Internal values |
| --- | --- | --- |
| Agent | Definition, instance, Ref, Turn, Outcome, Directives, and callback values | Validation and command runner support data |
| Plugin | Declaration, manifest, Init, owner callback contexts, preparations, transitions, and contributions | `Jido.Plugin.Spec` and all four facet Specs |
| Agent Server | Public functions, OTP results, status, snapshot, child, relationship, and debug maps | `ChildInfo`, `ParentRef`, Active Turn, runtime checkpoint, and Runtime Store data |
| Persistence | Adapter byte protocol and documented operation results | Record, checkpoint composition, key selection, and revision implementation data |
| Jido instance | Generated and root lifecycle functions, optional namespace, Ref facade, PIDs, names, counts, and bindings | Namespace and instance service implementation data |
| Topology | Definitions, instances, plans, Builder, Codec, Plugin context and contribution, Controller status, readiness, repair, and lookup | Contribution Specs and Controller runtime state |
| Authoring extension | Agent and Topology extension modules and canonical returned data | DSL collection and lowering support data |
| Observation | Error projection version 1 and owner-defined semantic facts | Handler and buffer implementation data |

The revalidation confirms these seam-90 rules:

- `Jido.Plugin.Spec` stays internal. Public declarations and callback values
  stay public.
- `Jido.AgentServer.ChildInfo`, `Jido.AgentServer.ParentRef`, and
  `Jido.RuntimeStore` stay internal.
- Public authoring extensions return canonical Agent or Topology data. Their
  private normalization types do not become public.
- Adjacent `jido_action` and `jido_signal` errors keep their package owner.

## Raw protocol controls

The full registry stays in the selected design. Owner-seam additions are:

- Persistence load can return `:not_found` or `:deleted`. Required writes can
  return confirmed `:conflict`, documented `{:rejected, reason}`, explicit
  indeterminate results, or another preserved adapter reason.
- Ref resolution can return `{:ok, pid}` or `{:error, :not_found}`. Ref delete
  can also return `:agent_running`. Namespace and option failures use registered
  validation codes.
- Agent Server keeps cancellation, readiness, lifecycle, request, cast,
  inspection, and OTP results documented by its owner.
- Topology Controller keeps `:ok` for accepted repair and readiness, a status
  map, PID-or-`nil` lookup, and normal OTP start and stop results.
- Explicit known-node child placement keeps confirmed, indeterminate, and
  unreachable result meanings. These are not authority grants.

No raw control was removed or changed by this seam.

## Evidence matrix

| Requirement group | Evidence | State |
| --- | --- | --- |
| `ERR-REQ-001` to `ERR-REQ-005` | Error module, class, composition, and 21-code registry tests | `Proven` |
| `ERR-REQ-006` to `ERR-REQ-010` | Agent, Plugin, Persistence, Exec, Topology Plugin, and callback-fault tests | `Proven` |
| `ERR-REQ-011` | Runtime owner crash-policy and supervisor tests | `Proven` for current owned invariants |
| `ERR-REQ-012`, `ERR-REQ-013` | Persistence lifecycle, write-result, and authority-loss tests | `Proven` |
| `ERR-REQ-014` | Plugin, Exec, and whole-Turn timeout tests | `Proven` for current owned limits |
| `ERR-REQ-015`, `ERR-REQ-016` | Current protocol registry and owner API tests | `Proven` |
| `ERR-REQ-017`, `ERR-REQ-018` | Exact projection and hostile transport tests | `Proven` |
| `ERR-REQ-019` | No named version-2 consumer exists | `Retired` |
| `ERR-REQ-020`, `ERR-REQ-021` | Revalidated public and internal value inventory | `Proven` |
| `ERR-REQ-022` to `ERR-REQ-024` | Agent, Plugin, checkpoint, record, and persistence portability tests | `Proven` |

## Canonical implementation

| Contract | Source |
| --- | --- |
| Five error classes and six public error modules | `Jido.Error` |
| Closed stable-code registry and lookup | `Jido.Error.stable_codes/0` and `code/1` |
| Bounded projection version 1 | `Jido.Error.to_map/1` |
| Callback fault containment | Agent, Plugin, Persistence, and Exec owner modules |
| Whole-Turn operation limit | `Jido.AgentServer` |
| Instance and namespace validation | `Jido.Instance.Options`, `NamespaceRegistry`, and `RefFacade` |
| Portable recursive term check | `Jido.PortableTerm` |
| Early Agent acceptance | `Jido.Agent.State` and `Jido.Agent` |
| Persistence defense in depth | `Jido.Persistence.Record` |

## Compatibility decisions

- Keep five Splode classes and six current Jido error modules.
- Keep `CompensationError` until `jido_action` has a proved replacement.
- Keep stable atoms in `details.code`; do not add a top-level projection code.
- Keep exact callback-returned error reasons.
- Keep current raw protocol controls until the operation owner supplies staged
  migration proof.
- Keep exact projection version 1. A new projection requires a named consumer.
- Keep current public PID, Ref, OTP, map, tuple, atom, and keyword forms.
- Add codes only at Jido-owned conversions. Never reuse a code or match a
  message.

## Verification record

- Focused error, versioning, portability, Plugin, Ref, and Agent Server context
  tests: 159 passed.
- Definition-revision research example: 2 passed.
- `mix quality`: 1,182 passed, 1 expected exclusion, with clean Credo and
  Dialyzer results.
- `mix docs --warnings-as-errors`: passed.
- `git diff --check`: passed.

## Completion criteria

- [x] Five classes and six Jido error modules match source.
- [x] Every Jido-owned literal in `details.code` is in the 21-code registry.
- [x] The three previously unregistered owner codes have real-path tests.
- [x] Callback-returned errors remain exact.
- [x] Callback invalid output, fault, task loss, and owned timeout have owner
      conversions.
- [x] Raw controls have an owner and compatibility rule.
- [x] Public shaped values and internal support values are distinct.
- [x] Package-boundary extension categories are in the inventory.
- [x] Error projection version 1 is exact, bounded, and sanitized.
- [x] Portable values fail at their owned acceptance boundaries and again at
      persistence.
- [x] No new error class or projection version is needed.
