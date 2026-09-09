> Approved target seam design. Dependent owner-seam details remain open.

# Errors and public contracts design

The requirements and decisions in this document were approved on 2026-09-09. The
[design review index](../README.md#document-review-status) is the source of
truth for approval.

## Scope and owner

- Owner: `Jido.Error` and the shared public-contract policy.
- In scope: Jido error classes, stable Jido codes, callback normalization,
  protocol controls, error projection, shaped success values, and portable
  values.
- Out of scope: persistence retry and restart policy, Plugin authority,
  cancellation policy, overload policy, runtime topology, and Telemetry event
  schemas.
- Adjacent owners: `jido_action` owns Action, Flow, and compensation concepts.
  `jido_signal` owns Signal routing, dispatch, and bus failures. Jido preserves
  an adjacent package error when its callback contract returns that error.

## Model

A Jido boundary first identifies the source of a failure. It then applies one
of three rules:

```text
declared callback error  -> preserve the returned reason
Jido-owned conversion    -> Jido error class + stable details.code
registered protocol      -> preserve the documented raw control
```

A class states what kind of failure occurred. A code states which stable
Jido-owned conversion occurred. A message gives information to a person. A
caller shall not use a message as a program key.

The stable code is in `error.details.code`. This location keeps every current
error struct and preserves the exact `Jido.Error.to_map/1` shape. Callers use
`Jido.Error.code/1` to read a registered Jido code.

## Requirements

These EARS requirements define the target. Their identifiers are stable.

### Taxonomy and ownership

`ERR-REQ-001`: The Jido error boundary shall provide the Splode classes
`:invalid`, `:execution`, `:routing`, `:timeout`, and `:internal`.

`ERR-REQ-002`: The Jido error boundary shall give each Jido error module one
fixed class and one documented module-specific field set.

`ERR-REQ-003`: When Jido converts a failure, the owning boundary shall use a
registered Jido atom code in `error.details.code`.

`ERR-REQ-004`: When an adjacent package or application callback returns an
error reason, the Jido boundary shall preserve that reason unless the callback
contract explicitly requires a Jido conversion.

`ERR-REQ-005`: While `Jido.Error.CompensationError` remains public, the Jido
error boundary shall preserve its current execution-class behavior until an
approved `jido_action` migration has replacement proof.

### Public results and normalization

`ERR-REQ-006`: When a public Jido function owns failure conversion, the
function shall return `{:error, error}` with a defined Jido or adjacent Splode
error unless the protocol registry permits a raw value.

`ERR-REQ-007`: When a bang function receives an error from its tagged
counterpart, the bang function shall raise that same error.

`ERR-REQ-008`: When a declared callback returns `{:error, reason}`, the owning
Jido boundary shall preserve `reason` exactly, including an already composed
Splode error.

`ERR-REQ-009`: If a declared callback returns a value outside its success and
error contract, then the owning Jido boundary shall return its registered
invalid-callback-result error.

`ERR-REQ-010`: If a declared callback raises, throws, or exits, then the owning
Jido boundary shall return its registered callback-failed error.

`ERR-REQ-011`: If Jido detects a broken internal invariant, then the live Jido
process shall exit through OTP instead of returning an ordinary application
failure.

`ERR-REQ-012`: While public persistence control migration is not approved,
`Jido.Persistence` shall preserve documented adapter error reasons and shall
convert only invalid adapter replies and adapter faults.

`ERR-REQ-013`: If a persistence write result is indeterminate, then the Agent
Server shall remove that activation's write authority before it admits another
Turn.

`ERR-REQ-014`: When owned Plugin or Exec work reaches its Jido operation limit,
the operation owner shall return a `TimeoutError` with its registered timeout
code. A caller wait timeout remains an OTP caller control.

### Protocol controls

`ERR-REQ-015`: Where a public function implements a registered application,
Map-like, OTP, lifecycle, or adapter protocol, the function shall use only the
raw values listed in the protocol registry.

`ERR-REQ-016`: When a new raw public control is proposed, the public-contract
owner shall record its boundary, meaning, and migration owner before release.

### Error projection

`ERR-REQ-017`: When Jido projects an error with `Jido.Error.to_map/1`, the error
boundary shall return the exact top-level keys `type`, `message`, `details`, and
`retryable?`.

`ERR-REQ-018`: When Jido projects an error, the error boundary shall bound
depth, collection size, and strings; redact sensitive keys; omit stacktrace
keys; make text valid UTF-8; and make the result JSON encodable.

`ERR-REQ-019` — Retired: This identifier proposed a projection version 2. No
current consumer requires it. The identifier shall not be reused. A future
projection needs a named consumer and migration proof.

### Shaped and portable values

`ERR-REQ-020`: When Jido publishes a shaped success value, its owner shall
document its purpose, validation entry, result form, and compatibility rule.

`ERR-REQ-021`: When a public value is a protocol map, tuple, atom, PID, OTP
name, or keyword list, its owner shall document why it uses that form.

`ERR-REQ-022`: When Agent accepts state, including Plugin-owned state keys, or
when Agent accepts a checkpoint, it shall reject every PID, port, reference,
function, improper list, and non-byte-aligned bitstring.

`ERR-REQ-023`: If portable-value validation fails, then the value owner shall
return a `ValidationError` with code `:non_portable_term` and a path with no
more than 20 segments. Each printed segment shall contain no more than 64
bytes. The path shall not contain the rejected value.

`ERR-REQ-024`: Where persistence is configured, the persistence boundary shall
validate the complete record before save and after load, even when Agent
already validated its state and checkpoint.

## Public error contract

### Error classes and modules

The audit keeps the current taxonomy. A separate persistence or runtime class
would classify an area, not a stable failure kind. For example, a persistence
record can be invalid, an adapter can fail during execution, and an operation
can time out. Those meanings already fit the five classes.

| Error module | Class | Public purpose |
| --- | --- | --- |
| `Jido.Error.ValidationError` | `:invalid` | Invalid input, option, schema, state, checkpoint, or callback output |
| `Jido.Error.ExecutionError` | `:execution` | Failed callback or executable work |
| `Jido.Error.RoutingError` | `:routing` | Failed Signal route or dispatch selection |
| `Jido.Error.TimeoutError` | `:timeout` | A Jido-owned operation limit |
| `Jido.Error.CompensationError` | `:execution` | Existing compensation compatibility API |
| `Jido.Error.InternalError` | `:internal` | Unexpected internal failure that can safely cross a value boundary |

Splode adds its own framework fields. Each module keeps its documented
module-specific fields. This seam does not replace the structs with one common
struct. It does not add `PersistenceError` or `RuntimeError`.

### Stable code registry

This registry is closed for this alignment. A later owner can add a code only
with a requirement, tests, and a dependent-document update. A code is never
reused for a different meaning.

| Code | Error class | Owner and trigger |
| --- | --- | --- |
| `:non_portable_term` | `:invalid` | Agent or Persistence rejects a prohibited nested term. |
| `:agent_invalid_callback_result` | `:invalid` or `:execution` | Agent persistence, signal, or executable callback output breaks its contract. |
| `:agent_callback_failed` | `:execution` | Agent persistence or `handle_signal/2` raises, throws, or exits. |
| `:plugin_invalid_callback_result` | `:execution` | A Plugin callback output has the wrong shape or breaks its value rules. |
| `:plugin_callback_failed` | `:execution` | A Plugin callback raises, throws, or exits. |
| `:plugin_callback_timeout` | `:timeout` | Owned readiness, admission, or Directive work reaches its operation limit. |
| `:plugin_callback_task_failed` | `:execution` | Owned admission or Directive work exits before a result. |
| `:persistence_invalid_callback_result` | `:execution` | A persistence adapter reply has an invalid shape. |
| `:persistence_callback_failed` | `:execution` | A persistence adapter call raises, throws, or exits. |
| `:agent_exec_invalid_callback_result` | `:execution` | An Exec adapter callback output has the wrong shape. |
| `:agent_exec_callback_failed` | `:execution` | An Exec adapter callback raises, throws, or exits. |
| `:agent_exec_callback_timeout` | `:timeout` | An Exec adapter callback reaches its operation limit. |
| `:agent_exec_callback_task_failed` | `:execution` | The owned Exec adapter process cannot start or exits. |

`Jido.Error.code/1` returns only a code in this registry. It accepts an error,
an `{:error, error}` pair, or the v1 projection map. An adjacent-package code
stays under that package's ownership and is not added by inference.

### Normalization matrix

| Source at a Jido boundary | Result | Compatibility rule |
| --- | --- | --- |
| `{:error, reason}` from a declared callback | Preserve `reason` exactly | Existing callbacks use `term()` error reasons. |
| Already composed Jido, Action, or Signal error | Preserve the error | Do not copy an adjacent error into a new Jido error. |
| Invalid callback output | Owner validation or execution error with an invalid-result code | The owner selects the class from the failed contract. |
| Callback raise, throw, or exit | Owner `ExecutionError` with a callback-failed code | Keep bounded diagnostic data in `details`. |
| Owned task exit | Owner `ExecutionError` with a task-failed code | Do not leak the monitor envelope. |
| Owned operation limit | Owner `TimeoutError` with a timeout code | Do not confuse it with caller wait timeout. |
| Persistence adapter control | Preserve at Adapter and current Persistence APIs | Seams 07 and 08 own any later public conversion. |
| Broken Jido invariant | OTP process exit | The runtime owner defines the invariant. |

This matrix is intentionally narrow. It does not convert every atom or tuple
in one release. Such a conversion would change current lifecycle and
application contracts without owner policy.

## Protocol control registry

The following raw values are public by design. A row can contain several
values when they are one protocol family.

| Boundary | Raw values and meaning | Owner and disposition |
| --- | --- | --- |
| Declared Agent and Plugin callbacks | `{:error, reason}` carries an application error reason. | Callback owner; retain exact reason. |
| `Jido.Persistence.Adapter` callbacks | `:ok`, `{:ok, bytes}`, and `{:error, reason}`; `:not_found`, `:conflict`, and `:indeterminate` have defined storage meanings. | Seam 07; retain inside adapter protocol. |
| Current `Jido.Persistence` operations | `:ok`, `{:ok, agent}`, `{:ok, agent, revision}`, or `{:error, reason}`. | Seam 07; retain until its public migration is approved. |
| `AgentServer.start_link/1`, `start/1`, `child_spec/1`, and `stop/3` | Standard OTP and supervisor start, child-spec, and stop values. | OTP protocol; retain. |
| `AgentServer.call/3` and async request pair | Agent result plus standard `:gen_statem` call, request, timeout, and process-down behavior. | Seam 08 and OTP; retain. |
| `AgentServer.cast/2` and `touch/1` | `:ok` means the message was sent. It does not confirm execution. | OTP cast protocol; retain. |
| `AgentServer.whereis/3`, `alive?/1`, and `via_tuple/3` | PID or `nil`, boolean, and Registry via tuple. | Registry and OTP protocol; retain. |
| `AgentServer.cancel/2` and `cancel_turn/3` | `:ok`, `:idle`, `:directing`, `:stale_turn`, `:cancelled`, and callback-owned error reasons. | Seam 08; retain until cancellation policy changes. |
| Agent Server inspection and ownership calls | `:debug_not_enabled`, `:plugin_not_declared`, `:not_running`, child and parent control tuples, and documented success maps. | Seam 08; retain until each owner migration. |
| `Jido.stop_agent/1..3`, `hibernate/1..3`, and `thaw/2..4` | Current lifecycle controls, including `:not_found`, `:not_running`, and timeout or persistence reasons. | Seam 09; retain until lifecycle policy changes. |
| `Jido.whereis_agent/1..3`, `list_agents/0..2`, and `agent_count/0..2` | PID or `nil`, `{id, pid}` list, and count. | Registry query protocol; retain. |
| `Jido.agent_parent_binding/1..3` | `{:ok, binding}` or Map-like `:error`. | Runtime-store lookup protocol; retain. |

The raw control registry does not make each value a good final product API. It
makes the current contract explicit and gives its owner a safe migration gate.

## Public result and shaped-value inventory

This is the consolidated inventory for the foundational seam. A later seam can
refine its owned value, but it shall keep the compatibility disposition.

### Exported failure positions

| API group | Success shape | Failure position | Owner and disposition |
| --- | --- | --- | --- |
| Agent `new`, `instantiate`, `validate`, schema composition, `set`, and `transition` | `Jido.Agent` or schema | Defined validation or adjacent error | Seam 01; retain. Bang forms raise the tagged error. |
| Agent `cmd` and `handle_signal` | Agent, `Turn`, and Directive list | Returned callback reason, routing error, or Jido conversion code | Seams 01 and 04; use the normalization matrix. |
| Agent `checkpoint` and `restore` | Versioned checkpoint map or Agent | Returned callback reason, portability error, or Jido conversion code | Seams 01 and 07; retain checkpoint contract. |
| Plugin declaration, schema, and state helpers | `Plugin.Spec`, schema, command, state, or child specs | Defined validation, callback reason, or Plugin conversion code | Seam 05; use the normalization matrix. |
| Plugin readiness, admission, dispatch, and Directive validation | `:ok`, command, Signal, or Directive | Returned callback reason or Plugin conversion code | Seam 05; use the normalization matrix. |
| Persistence configuration and operations | Adapter pair, Agent, revision, or `:ok` | Current adapter reason or persistence conversion code | Seam 07; keep raw controls until owner migration. Invalid direct adapter configuration can raise `ArgumentError`. |
| Agent Server start and Signal work | OTP start value or Agent | Startup controls, returned application reason, or owned conversion code | Seam 08; keep lifecycle controls, add codes only to owned conversions. |
| Agent Server control and inspection | `:ok`, PID, Agent, status map, snapshot map, child map, or event list | Registered raw lifecycle and OTP controls | Seam 08; retain until owner migration. |
| Jido instance and Agent lifecycle | OTP start value, `:ok`, PID, list, count, or binding | Registered raw lifecycle and OTP controls | Seam 09; retain until owner migration. |
| Error constructors and helpers | Error struct, code, retry flag, or v1 map | Constructors do not return tagged failures | Seam 12; keep exact structs and projection. |

### Shaped success values

| Value | Purpose and validation entry | Compatibility disposition |
| --- | --- | --- |
| `Jido.Agent` | Canonical definition or instance; `Agent.new/1`, `instantiate/2`, and validation functions | Retain the approved seam-01 struct. |
| Agent public map | Complete Agent inspection form; `Agent.to_map/1` | Retain the map and its current keys. It is not the error projection. |
| Agent checkpoint map | Portable restore envelope; `Agent.checkpoint/2` and `restore/3` | Retain versioned checkpoint semantics. |
| `Jido.Agent.Turn` and `Outcome` | Prepared work and completed runtime outcome; their constructors and validators | Retain; seams 04 and 08 own fields. |
| `Jido.Plugin.Spec`, `Init`, and callback contexts | Normalized Plugin declaration and runtime callback data; Plugin normalization and Zoi validators | Retain; seam 05 owns fields. |
| Agent Directive structs | Typed effect requests; Directive constructors and validators | Retain; seam 06 owns fields. |
| Agent Server status, snapshot, child, relationship, and event maps | Narrow inspection and protocol views; built by Agent Server | Retain maps; seam 08 owns fields and versioning. |
| Registry PID, via tuple, OTP name, and `{id, pid}` list | Direct OTP and Registry interoperation | Retain protocol shapes. |
| Instance name and partition-key helpers | Module atoms and tagged partition tuples for local runtime addressing | Retain current helper results. Seam 09 owns later Ref migration. |
| Persistence record and adapter bytes | Internal durable envelope and adapter wire value; Persistence encode/decode validators | Keep record internal and byte protocol public. |
| Error v1 map | Bounded observation and transport view; `Jido.Error.to_map/1` | Retain exact top-level keys. |

## Error projection

`Jido.Error.to_map/1` remains the only projection:

```elixir
%{
  type: :execution_error,
  message: "Agent callback failed",
  details: %{code: :agent_callback_failed, callback: :handle_signal},
  retryable?: true
}
```

The four top-level keys are exact. A stable code remains inside `details`.
`to_map/1` also accepts arbitrary terms because crash reporting must not fail
while it renders an unexpected reason. It bounds and sanitizes those terms. It
does not promise that every general `details` key is semantically safe for an
untrusted audience. A caller that adds sensitive details still owns that data.

There is no version 2. Seam 13 can reopen this decision only after it identifies
a consumer that cannot use the current map.

## Portable-value contract

A portable value can contain atoms, numbers, booleans, `nil`, byte-aligned
binaries, proper lists, tuples, maps, and structs whose full contents are
portable. It cannot contain a PID, port, reference, function, improper list,
or non-byte-aligned bitstring.

Agent validates complete accepted state, including Plugin-owned keys. Agent
also validates checkpoint output and restore input. Persistence validates the
full record before encode and after decode. The persistence check is defense
in depth, not the first state check.

A failure path starts with an owned root such as `:agent_state`, `:checkpoint`,
or `:record`. Map keys that are not safe short atoms, small integers, or
binaries use a positional marker. Paths contain at most 20 segments. Long
printable segments are cut to 64 bytes. The rejected value is never copied
into the error.

## Invariants

- `ERR-INV-001`: One Jido-owned conversion has one class, code, and owner.
- `ERR-INV-002`: A message is not a program decision key.
- `ERR-INV-003`: A raw control does not appear outside this registry without a
  reviewed owner change.
- `ERR-INV-004`: A callback-returned application error remains exact.
- `ERR-INV-005`: A callback fault becomes an owned error; a broken Jido
  invariant remains an OTP failure.
- `ERR-INV-006`: A bang API and its tagged API use one error path.
- `ERR-INV-007`: The v1 projection is bounded, sanitized, and exact at the top
  level.
- `ERR-INV-008`: Agent state and durable records are recursively portable at
  their owned acceptance boundaries.
- `ERR-INV-009`: A current public result stays valid until its owner supplies
  migration proof.

## Decisions

| ID | Question | Decision | Effect |
| --- | --- | --- | --- |
| `ERR-DEC-001` | Which core taxonomy applies? | Keep five Splode classes and six current errors. Do not add persistence or runtime classes. | The taxonomy follows failure kind, not subsystem. |
| `ERR-DEC-002` | Where does a stable code live? | Use registered atoms in `details.code` and expose `Jido.Error.code/1`. | No error-struct or projection-shape replacement is needed. |
| `ERR-DEC-003` | How do callbacks fail? | Preserve returned error reasons. Convert invalid output, raise, throw, exit, task loss, and owned timeout at the owning boundary. | Compatibility and containment both stay explicit. |
| `ERR-DEC-004` | How does projection change? | Keep exact v1 and retire the speculative v2 requirement. | Current observation and transport consumers do not migrate. |
| `ERR-DEC-005` | Can projection accept arbitrary terms? | Yes, as a defensive crash-reporting contract. Keep bounds and sanitization. | Unexpected reporting cannot raise. |
| `ERR-DEC-006` | Which raw controls remain? | Keep only the controls in this registry until their owner approves a migration. | Existing lifecycle and adapter behavior does not change by accident. |
| `ERR-DEC-007` | Where does portability run? | Run it at Agent state and checkpoint acceptance, and again at persistence record save and load. | Invalid runtime values fail early and storage remains protected. |
| `ERR-DEC-008` | How is Splode composition selected? | Keep the current core composition and preserve adjacent errors returned by callbacks. | This seam does not invent instance composition options. |

## Downstream guarantees

| Consumer seam | Foundational guarantee |
| --- | --- |
| 01 Agent and 04 Turn evaluation | Agent state and checkpoints are portable; callback conversions use registered Agent codes. |
| 05 Plugins | Plugin callback faults, invalid outputs, task loss, and operation limits have registered codes. Returned errors remain exact. |
| 07 Persistence | Adapter faults and invalid replies have registered codes. Raw adapter controls and public migration remain seam-07 decisions. |
| 08 Agent Server and 09 Jido instance | Current lifecycle controls stay registered. Exec conversion codes are stable. Final lifecycle migration stays with each owner. |
| 13 Observability | Exact v1 projection remains available. No v2 migration is required. |
| 90 Package boundaries | Adjacent package errors keep their owner and do not require copied Jido modules. |
