---
title: Jido.Id component
status: current
last-reviewed: 2026-11-10
---

# Jido.Id component

`Jido.Id` creates and checks the RFC 9562 UUID formats used by Jido.

## Public contract

| Operation | Contract |
| --- | --- |
| `uuid7/0` | Returns a new UUIDv7 with the current Unix millisecond timestamp and random data. |
| `uuid7?/1` | Reports whether a value is a valid UUIDv7. |
| `uuid7_timestamp/1` | Returns the Unix millisecond timestamp from a valid UUIDv7. It raises for invalid input. |
| `compare_uuid7/2` | Compares the complete binary values of two valid UUIDv7 values. It returns `:lt`, `:eq`, or `:gt`. |
| `uuid8/1` | Formats the first 16 bytes of caller-owned data as UUIDv8. It raises when fewer than 16 bytes are supplied. |

## Contract invariants

- UUIDv7 values from different milliseconds sort by time.
- UUIDv7 values from the same millisecond have random order.
- The component does not keep a process-local sequence counter.
- UUIDv8 assigns the RFC version and variant bits.
- The caller owns the meaning and stability of UUIDv8 input bytes.

## Architectural boundary

### Owns

- UUIDv7 generation, recognition, timestamp extraction, and comparison.
- UUIDv8 formatting from deterministic caller bytes.

### Does not own

- Domain identity rules for Agents, Signals, Sessions, Threads, Flows, or audit
  records.
- Persistence keys or Catalog references.
- Monotonic ordering inside one millisecond.
- Distributed uniqueness guarantees beyond the UUID format and random source.

### Dependency position

`.reach.exs` places `Jido.Id` in `primitives`. Its direct system dependencies
are time and cryptographic random bytes. Signal, Session, Thread, Flow identity,
AI request context, topology, and audit code consume it.

## Covenant and evidence

There is no focused active Covenant component for `Jido.Id`. Unit tests cover
the current API in `test/jido/id_test.exs`.

The missing focused Covenant owner is a proof gap. It does not mean that the
public contract is undefined.

## Boundary review

The source and Reach boundary are small and coherent. The required follow-up is
proof ownership, not a source split.

## Sources

- [`Jido.Id`](../../lib/jido/id.ex)
- [ID tests](../../test/jido/id_test.exs)
- [Reach layers](../../.reach.exs)

