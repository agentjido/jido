> Implemented seam review entry point.

# 12 - Errors and public contracts

## Briefing

Jido uses five Splode error classes: `:invalid`, `:execution`, `:routing`,
`:timeout`, and `:internal`. Six Jido error modules use those classes.
`Jido.Error.CompensationError` stays as a compatible execution error.

A class states the failure kind. A stable code states which Jido-owned
conversion produced the error. Codes live in `error.details.code` and are read
with `Jido.Error.code/1`. The closed registry now contains every code that Jido
source emits in that position.

The owner seams added definition, checkpoint, Plugin-owned-field protection,
whole-Turn timeout, instance configuration, and namespace results. Seam 12
registers those existing results without renaming them. This is additive:
callers that already inspect `details.code` keep the same value.

## Failure rules

| Source | Public result |
| --- | --- |
| Declared callback returns `{:error, reason}` | Preserve `reason` exactly. |
| Callback returns an invalid shape | Return an owner error with a registered invalid-result code. |
| Callback raises, throws, or exits | Return an owner `ExecutionError` with a registered callback-failed code. |
| Owned task exits | Return the owner task-failed code. |
| Owned operation reaches its limit | Return `TimeoutError` with the owner timeout code. |
| Documented raw protocol control | Preserve the registered raw value. |
| Broken live-process invariant | Exit through OTP. |

Persistence adapter controls, OTP start and stop results, cancellation values,
PID lookup, Map-like lookup, and best-effort cast results keep their documented
forms. This seam does not convert all atoms and tuples into exceptions.

## Projection and portable values

`Jido.Error.to_map/1` keeps exactly four top-level keys: `type`, `message`,
`details`, and `retryable?`. It bounds depth, collection size, and text. It
redacts sensitive keys, removes stacktraces, repairs invalid UTF-8, and returns
JSON-safe data. There is no projection version 2.

Complete Agent state, checkpoint values, and complete persistence records
reject PIDs, ports, references, functions, improper lists, and
non-byte-aligned bitstrings at their owned acceptance boundaries. Persistence
checks the complete record again as defense in depth.

## Public value ownership

- `Jido.Agent.Ref`, Agent definitions and instances, Turn, and Outcome belong
  to their Agent owners.
- Plugin manifests and callback values are public. `Jido.Plugin.Spec` and the
  four owner-facet Specs are internal normalization data.
- `Jido.AgentServer.ChildInfo`, `Jido.AgentServer.ParentRef`, and
  `Jido.RuntimeStore` are internal support values. Public child, parent,
  snapshot, status, and debug results keep their documented map or control
  forms.
- Persistence records are internal. Adapter bytes and adapter controls are the
  public provider protocol.
- Topology definitions, instances, plans, Plugin contexts and contributions,
  Controller status, readiness, repair, and lookup results belong to the
  Topology owner.
- Authoring extensions are public modules and canonical data boundaries. Their
  private normalization data is not public.

## Compatibility

- Do not match error messages as program keys.
- Do not copy an adjacent `jido_action` or `jido_signal` error into a new Jido
  error.
- Keep raw controls until their operation owner approves and proves a staged
  migration.
- Keep the exact error projection version 1.
- Add a stable code only with an owner, a trigger, tests, and a documentation
  update. Never reuse a code.
- Keep current PID, Ref, OTP, map, tuple, atom, and keyword results during V3.

## Evidence

- Error tests prove the 21-code registry, code lookup, class behavior, and the
  exact version-1 projection.
- Agent and Plugin tests prove the added checkpoint, definition, and state-owner
  codes on their real failure paths.
- Agent Server and instance tests prove Turn timeout, instance configuration,
  namespace binding, required namespace, and namespace mismatch codes.
- Callback and task tests prove returned-error preservation, invalid result,
  fault, task-loss, and operation-limit handling.
- Portability and error-transport tests prove all prohibited term classes,
  bounded paths, redaction, UTF-8 repair, and JSON safety.

## Follow-on seams

- 13 Observability consumes the exact version-1 projection and stable codes.
- 99 Delivery rechecks the public inventory and complete release set.

## Documents

- [Selected design](design.md)
- [Implemented alignment and evidence](alignment.md)
