> Approved seam review entry point. Dependent owner-seam work remains open.

# 12 — Errors and public contracts

## Briefing

This seam defines how Jido carries a failure across a public boundary. It also
records the public success shapes, raw protocol controls, error projection, and
portable-value rule that other seams use.

The contract and its implementation evidence are approved.

The audit rejected two proposed error classes. Jido does not need a
`:persistence` class or a `:runtime` class now. Persistence and runtime are
operation areas, not stable failure kinds. The current five Splode classes are
enough: `:invalid`, `:execution`, `:routing`, `:timeout`, and `:internal`.
`CompensationError` stays as a compatibility error.

The audit also rejected a projection version 2. There is no current consumer
that needs it. `Jido.Error.to_map/1` keeps its exact four top-level keys:
`type`, `message`, `details`, and `retryable?`.

## Approved inputs and current limits

- [00 Overview](../00_overview/README.md) is approved.
- [01 Agent](../01_agent/README.md) is approved at commit `fa17a6d6`.
- [90 Package boundaries](../90_package-boundaries/README.md) is still pending.
  This seam uses only its narrow package-ownership rule.
- Operation policy stays with seams 05, 07, 08, and 09. This seam does not
  invent persistence retry, restart, cancellation, or overload policy.

## Contract summary

| Area | Contract |
| --- | --- |
| Error classes | Keep the five current Splode classes and six current Jido error modules. |
| Stable codes | Store Jido-owned codes in `error.details.code`; read them with `Jido.Error.code/1`. |
| Returned callback errors | Preserve `{:error, reason}` exactly. The callback contract already permits an application term. |
| Invalid callback output | Convert it to an owner error with an `*_invalid_callback_result` code. |
| Callback fault | Convert raise, throw, or exit to an owner `ExecutionError` with an `*_callback_failed` code. |
| Owned work loss | Convert task loss and operation limits to owner task-failure or timeout codes. |
| Internal invariant | Let the live process exit through OTP. Do not present it as an application failure. |
| Projection | Keep the exact, bounded, sanitized v1 map. Do not add v2 without a real consumer. |
| Portable values | Reject PIDs, ports, references, functions, improper lists, and non-byte-aligned bitstrings before acceptance. Keep persistence checks as defense in depth. |

## What changed in this alignment

- Added one closed Jido code registry and `Jido.Error.code/1`.
- Added codes to Agent, Plugin, persistence, and Exec conversions that already
  produce a Jido error.
- Contained `handle_signal/2` raise, throw, and exit failures.
- Kept callback-returned application errors and current lifecycle controls
  unchanged.
- Bounded every portability path to 20 segments and each printed segment to 64
  bytes.
- Added focused tests for codes, callback matrices, timeouts, task loss,
  projection shape, and persistence defense in depth.

## Major gaps and work remaining

- Seam 05 owns final Plugin value and lifecycle meanings.
- Seam 07 owns public persistence control migration and write policy.
- Seam 08 owns Agent Server lifecycle and cancellation migration.
- Seam 09 owns instance lifecycle migration.
- Seam 13 can propose a new projection only with a named consumer and a
  migration test.

These items do not block the foundational contract. They block only a later
change to the listed operation.

## Approved decisions

1. Approve the five-class taxonomy and keep `CompensationError`.
2. Approve `details.code` and the closed code registry.
3. Approve the narrow callback matrix, including exact returned-error
   preservation.
4. Approve the closed raw-control registry.
5. Approve exact v1 projection retention and no speculative v2.
6. Approve early portable-value checks plus persistence defense in depth.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
