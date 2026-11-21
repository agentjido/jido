---
title: Jido.Error component
status: current
last-reviewed: 2026-11-10
---

# Jido.Error component

`Jido.Error` is the shared error value, normalization, and public projection
component for Jido.

## Public contract

The component exposes five public error types:

- `ValidationError`
- `ExecutionError`
- `RoutingError`
- `TimeoutError`
- `InternalError`

The root module provides these public operation groups:

| Surface | Public operations |
| --- | --- |
| Construction | `validation_error/1,2`, `config_error/1,2`, `execution_error/1,2`, `routing_error/1,2`, `timeout_error/1,2`, `internal_error/1,2` |
| Normalization | `normalize_details/1`, `validation_result/3,4` |
| Stable classification | `stable_codes/0`, `code/1`, `type/1`, `retryable?/1` |
| Public projection | `to_map/1` |
| Path handling | `set_path/2`, `prefix_path/2`, `prefix_result_path/2` |

Splode also generates shared conversion and traversal functions on
`Jido.Error`. These include `to_class/1,2`, `to_error/1,2`, `traverse_errors/2`,
and `unwrap!/1,2`.

## Contract invariants

- Program logic uses stable codes. It does not match human-readable messages.
- `to_map/1` returns the version-1 projection with exactly `type`, `message`,
  `details`, and `retryable?`.
- Transport projection bounds depth, collection size, text, and keys.
- Transport projection redacts sensitive values and repairs invalid UTF-8.
- Unknown values cannot make projection raise, throw, or exit.
- Domain components can add their own codes. They do not add shared error
  classes without changing this component contract.

## Architectural boundary

### Owns

- The shared Jido error taxonomy and constructors.
- Jido-owned stable error codes.
- Error normalization and path handling.
- Safe public projection and default retry classification.

### Does not own

- The point where a domain callback is invoked.
- Domain-specific recovery or retry policy.
- Signal delivery, Action execution, Agent commit, or persistence behavior.
- Codes owned by adjacent packages.

### Dependency position

`.reach.exs` places `Jido.Error` in `primitives`. The component has no allowed
dependency on a higher Jido layer. Most higher Jido layers consume it.

## Covenant and evidence

The active Covenant component is `jido.error`. Its six active obligations
cover taxonomy, stable codes, public projection, safe transport, retry
classification, and defensive rendering.

Primary evidence:

- `test/jido/error/api_test.exs`
- `test/jido/error/normalization_test.exs`
- `test/jido/error/transport_test.exs`
- `test/contracts/jido/error.obligations.md`

## Boundary review

The current source, Reach layer, and Covenant owner agree. No known module
ownership conflict exists for this component.

## Sources

- [`Jido.Error`](../../lib/jido/error.ex)
- [Error Covenant obligations](../../test/contracts/jido/error.obligations.md)
- [Reach layers](../../.reach.exs)

