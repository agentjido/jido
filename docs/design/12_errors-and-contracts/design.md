> Target seam design. This document is pending approval.

# Errors and public contracts design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. The prerequisite seams are also pending approval.

## Scope and owner

- Owner: `Jido.Error` and the cross-system public-contract policy.
- In scope: Jido error classes, stable program codes, error composition,
  normalization at public result boundaries, protocol controls, safe error
  projection, public shaped-value rules, and recursive portable-value rules.
- Out of scope: the failure state machine for an operation, exact Agent Ref or
  record fields, persistence retry policy, Plugin authority, Agent Server
  restart policy, and Telemetry event schemas.
- Adjacent owners: `jido_action` owns Action, Flow, and compensation failures.
  `jido_signal` owns Signal, routing, dispatch, and bus failures. Jido does not
  copy an adjacent package error that meets the composed Splode contract.

## Model

A Jido failure crosses three boundaries:

```text
owner fault or protocol control
  -> owner-specific normalization
  -> defined composed Splode error
  -> tagged result, raise, or bounded public projection
```

The operation owner defines what failed. This seam defines how the failure is
named and carried. A public code is for program decisions. A message is for a
person. A projection is for observation or transport. It is not a stored copy
of the exception.

Raw values are valid only inside a registered protocol. Examples are a
`Map.fetch/2` style `:error`, an OTP reply envelope, or a persistence adapter
compare-and-swap control. The owner converts a protocol failure before it
crosses a higher-level Jido command or lifecycle boundary.

A public shaped success value has one owner, one purpose, and one validation
entry. A value that can enter Agent or Plugin state, a checkpoint, a durable
work item, or a persistence record must also meet the recursive portable-value
contract.

## Requirements

These EARS requirements define the recommended target. Their identifiers are
stable. EARS syntax does not mean that a requirement is approved.

### Taxonomy and ownership

`ERR-REQ-001`: The Jido error boundary shall provide the Splode classes
`:invalid`, `:routing`, `:execution`, `:timeout`, `:persistence`, `:runtime`,
and `:internal`.

`ERR-REQ-002`: The Jido error boundary shall give each defined error module one
fixed class and one closed documented field set.

`ERR-REQ-003`: The Jido error boundary shall give each public Jido failure one
stable atom code with one operation owner and one documented meaning.

`ERR-REQ-004`: When an adjacent package returns a defined error accepted by the
active composed Splode, the Jido boundary shall preserve that error without
copying the package-owned concept into a Jido error.

`ERR-REQ-005`: While a core compatibility path for
`Jido.Error.CompensationError` remains supported, the Jido error boundary shall
preserve its current public behavior until an approved `jido_action` migration
has replacement proof.

### Public results and normalization

`ERR-REQ-006`: If a public Jido construction, command, or lifecycle operation
fails, then the operation owner shall return `{:error, error}` where `error` is
a defined composed Splode error, unless this design registers the result as a
protocol control.

`ERR-REQ-007`: When a bang function receives a failure from its tagged
counterpart, the bang function shall raise the same defined error.

`ERR-REQ-008`: When application callback work returns a defined composed
Splode error, the owning Jido boundary shall preserve that error.

`ERR-REQ-009`: If application callback work returns an invalid result or an
arbitrary failure term, then the owning Jido boundary shall return the defined
error code for that callback boundary.

`ERR-REQ-010`: If application callback work raises, throws, or exits, then the
owning Jido boundary shall return the defined error for that callback boundary.

`ERR-REQ-011`: If Jido detects a broken internal invariant, then the live Jido
runtime shall exit through OTP instead of reporting the fault as an ordinary
application failure.

`ERR-REQ-012`: When a persistence adapter returns `:not_found`, `:conflict`, or
`:indeterminate`, the public persistence operation shall convert that control
to a `Jido.Error.PersistenceError` with the same stable code before it returns
to a command or lifecycle caller.

`ERR-REQ-013`: If a persistence write result is indeterminate, then the Agent
Server shall remove the activation's write authority before it admits another
Turn.

`ERR-REQ-014`: When an operation reaches its own execution limit, the operation
owner shall use its registered timeout code instead of a caller wait-timeout
control.

### Protocol controls

`ERR-REQ-015`: Where a public function implements a registered Elixir, OTP, or
adapter protocol, the function shall return only the raw control values listed
for that protocol.

`ERR-REQ-016`: When a new raw public control value is proposed, the public-
contract owner shall add its meaning, boundary, and compatibility rule to the
protocol registry before release.

### Safe projection

`ERR-REQ-017`: When Jido projects a defined error for observation or transport,
the error boundary shall return bounded `class`, `type`, `code`, `message`, and
`retryable?` values plus only registered operation and identifier fields.

`ERR-REQ-018`: When Jido projects an error, the error boundary shall exclude
stacktraces, raw causes, Agent state, Plugin state, Signal data, checkpoints,
persistence records, Directive payloads, process handles, and caller context.

`ERR-REQ-019`: While projection consumers still require the current four-key
map, the error boundary shall provide a versioned compatibility form with
`type`, `message`, bounded `details`, and `retryable?`.

### Public shaped and portable values

`ERR-REQ-020`: When Jido publishes a shaped public success value, the value
owner shall document its owner, purpose, constructor or validator, fields,
result type, and compatibility rule.

`ERR-REQ-021`: When a public value is a protocol map, tuple, atom, PID, OTP
name, or keyword list, the value owner shall document why that protocol form is
used instead of a struct.

`ERR-REQ-022`: When a value enters Agent state, Plugin state, a checkpoint, a
durable work item, or a persistence record, the value owner shall reject each
PID, port, reference, function, improper list, or non-byte-aligned bitstring in
that value.

`ERR-REQ-023`: If recursive portable-value validation fails, then the value
owner shall return a `ValidationError` with code `:non_portable_term` and a
bounded path to the first rejected value.

`ERR-REQ-024`: Where persistence is configured, the persistence boundary shall
validate the complete encoded record before save and the complete decoded
record after load, even when an earlier owner validated its content.

## Public contract

### Error set

The recommended core set is:

| Error module | Class | Purpose |
| --- | --- | --- |
| `Jido.Error.ValidationError` | `:invalid` | Invalid input, option, schema, state, Directive, or callback result |
| `Jido.Error.RoutingError` | `:routing` | Missing, ambiguous, invalid, or undeliverable route |
| `Jido.Error.ExecutionError` | `:execution` | Action, Flow, Plugin callback, or Turn evaluation failure |
| `Jido.Error.TimeoutError` | `:timeout` | An operation-owned admission, Turn, readiness, Directive, or startup limit |
| `Jido.Error.PersistenceError` | `:persistence` | Load, write, conflict, indeterminate result, invalid record, or restore failure |
| `Jido.Error.RuntimeError` | `:runtime` | Lifecycle, overload, cancellation, reentry, Plugin runtime, Directive, or child failure |
| `Jido.Error.InternalError` | `:internal` | Broken Jido invariant or unexpected framework failure |

`Jido.Error.t()` is the union of core errors and errors accepted by the active
composed Splode. Direct Agent calls use the core composition. A future instance
composition needs a separate approved configuration contract. This seam does
not define that option.

Each target core error has this closed public field set. Optional fields use
`nil` when they do not apply.

```elixir
%{
  code: atom(),
  message: String.t(),
  retryable?: boolean(),
  operation: atom() | nil,
  path: list() | nil,
  identifiers: map()
}
```

The allowed identifier keys are `agent_id`, `agent_ref`, `plugin`, `turn_id`,
`signal_id`, and `directive_id`. An owner can use a key only after its value
type is public and approved. An error field does not contain full state,
payload, runtime, record, or callback values. A private diagnostic cause can
exist only outside the public error and projection. It must follow Logger and
OTP crash-report policy.

### Code registry

The registry starts with the codes whose meanings already cross several
boundaries. Operation owners can propose more codes, but cannot reuse a code
for another meaning.

| Class | Initial stable codes |
| --- | --- |
| `:invalid` | `:invalid_input`, `:invalid_options`, `:invalid_callback_result`, `:non_portable_term`, `:invalid_checkpoint`, `:invalid_persistence_record` |
| `:routing` | `:no_route`, `:ambiguous_route`, `:invalid_route`, `:invalid_delivery_target` |
| `:execution` | `:action_failed`, `:flow_failed`, `:plugin_callback_failed`, `:turn_failed` |
| `:timeout` | `:admission_timeout`, `:turn_timeout`, `:readiness_timeout`, `:directive_timeout`, `:startup_timeout` |
| `:persistence` | `:not_found`, `:conflict`, `:indeterminate`, `:unavailable`, `:definition_mismatch`, `:restore_failed` |
| `:runtime` | `:turn_cancelled`, `:no_active_turn`, `:turn_mismatch`, `:too_late`, `:not_running`, `:overloaded`, `:reentrant_admission`, `:plugin_runtime_failed`, `:directive_failed` |
| `:internal` | `:invariant_failed`, `:unexpected_failure` |

A persistence callback timeout for a write is `:indeterminate`, not a general
timeout code, because Jido cannot know whether the provider wrote the value.
The persistence owner decides whether to add such an execution limit.

### Normalization matrix

| Source | Boundary result |
| --- | --- |
| Defined composed error | Preserve the error |
| Registered provider control | Convert to the owning public error |
| Invalid callback return | Owner error with `:invalid_callback_result` |
| Arbitrary callback error term | Owner callback-failure code |
| Raise, throw, or application exit | Owner callback-failure code; keep safe diagnostics outside projection |
| Task down or operation limit | Owner runtime, execution, or timeout code |
| Broken Jido invariant | Exit the live runtime through OTP |

### Protocol registry

| Boundary | Allowed raw success or control |
| --- | --- |
| `Agent.fetch_state/2` and `Agent.fetch_plugin_state/3` | `:error`, as in `Map.fetch/2` |
| `AgentServer.receive_response/2` | Standard `:gen_statem` response, timeout, or request-down envelope |
| Best-effort `AgentServer.cast/2` and `touch/1` | `:ok` means that Jido sent the message only |
| Local lookup and liveness functions | PID or `nil`; boolean liveness result |
| `child_spec/1`, `start_link/1`, and normal OTP stop | Standard OTP values |
| `Jido.Persistence.Adapter` callbacks | Documented `:not_found`, `:conflict`, and `:indeterminate` controls inside the adapter protocol |

Inspection functions can return documented Agent structs or maps as success
values. Their failures still use defined errors. A higher-level Jido command or
lifecycle result cannot leak an adapter or OTP failure control unless it has a
separate row in this registry.

### Projection versions

The target projection is version 2:

```elixir
%{
  class: :persistence,
  type: :persistence_error,
  code: :conflict,
  message: "Agent record changed before commit",
  retryable?: true,
  operation: :commit,
  identifiers: %{agent_id: "agent-1"}
}
```

`type` stays an atom and keeps the current program-key role. It does not change
to a module name. During migration, version 1 keeps the exact current top-level
keys: `type`, `message`, `details`, and `retryable?`. Version 2 does not expose
the general `details` container. The implementation plan must define the
function names and default-version switch after seam 13 identifies consumers.

### Portable-value contract

A portable value can contain atoms, numbers, booleans, `nil`, byte-aligned
binaries, proper lists, tuples, maps, and structs whose complete contents are
portable. It cannot contain a PID, port, reference, function, improper list,
or non-byte-aligned bitstring.

The error path starts with the owned root, such as `:agent_state`,
`:plugin_state`, `:checkpoint`, or `:record`. Later segments identify a map key,
list index, tuple index, or struct field. The projection bounds the number of
segments and the printed size of each segment. It never includes the rejected
value.

## Invariants

- `ERR-INV-001`: One public failure meaning has one class, code, and owner.
- `ERR-INV-002`: A public message is not a program decision key.
- `ERR-INV-003`: Raw controls do not escape their registered protocol.
- `ERR-INV-004`: Application faults become defined errors; broken Jido
  invariants remain OTP failures.
- `ERR-INV-005`: Error projection is bounded and contains no state, payload,
  process handle, stacktrace, or raw cause.
- `ERR-INV-006`: A bang API and its tagged API use one error model.
- `ERR-INV-007`: A durable or state-bearing value is recursively portable
  before its owner accepts it.
- `ERR-INV-008`: A current public result remains supported until its staged
  migration has replacement proof.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 01 Agent and 04 Turn evaluation | Candidate validation and direct evaluation return defined errors and path-aware portability failures. |
| 05 Plugins | Callback and state boundaries use the same normalization and portable-value rules. |
| 06 Commit and effects | Commit and Directive failures have stable owner codes without changing commit semantics. |
| 07 Persistence | Adapter controls stay in the adapter protocol and become public persistence errors at higher boundaries. |
| 08 Agent Server and 09 Jido instance | Command, lifecycle, timeout, overload, reentry, and cancellation meanings use stable errors, except registered OTP controls. |
| 10 Runtime topology | Process and child faults have bounded public errors; OTP invariant failures still exit. |
| 13 Observability | Error projection has bounded stable class, type, code, retry, operation, and identifier fields. |
| 90 Package boundaries and ecosystem packages | Package-owned Splode errors compose without copying private concepts into Jido. |
| 99 Delivery | Each changed public failure and projection has a compatibility and release gate. |

## Open design decisions

All recommendations are pending approval.

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `ERR-DEC-001` | Which core taxonomy applies? | Use the seven classes and modules in this design. Keep compensation as a temporary compatibility API. | Persistence and runtime failures stop using execution errors or raw terms. |
| `ERR-DEC-002` | What is a stable program key? | Use a closed atom code registry. Keep messages descriptive only. | Callers can match codes across message changes. |
| `ERR-DEC-003` | How do callback faults cross Jido? | Use the normalization matrix and preserve already-composed errors. | Raises, throws, exits, and raw returns have consistent public meanings. |
| `ERR-DEC-004` | How does projection change? | Keep `type` as an atom. Add version 2 and retain the exact version-1 form during migration. | Existing telemetry and transport consumers can move in stages. |
| `ERR-DEC-005` | Can `to_map` accept arbitrary terms? | Keep an explicit defensive version-1 projection during migration. Limit the final typed projection to composed errors. | Crash reporting stays robust without weakening the target error type. |
| `ERR-DEC-006` | Which raw controls remain public? | Use only the protocol registry in this design. Add a reviewed row before any new control ships. | Raw atoms and tuples cannot spread without ownership. |
| `ERR-DEC-007` | Where does portability run? | Validate at Agent and Plugin state acceptance, checkpoint creation and restore, durable-work creation, and persistence save and load. | Nonportable data fails at the earliest owned boundary and again before storage. |
| `ERR-DEC-008` | How is active Splode composition selected? | Use core composition now. Defer instance-specific composition until seam 09 defines a public configuration contract. | This seam does not invent an instance option. |
