> Seam review entry point. This document is pending approval.

# 12 — Errors and public contracts

## Briefing

Jido now uses Splode errors, tagged results, bounded error projection, and a
recursive portability check. Public failures still use several error structs,
raw terms, atoms, tuples, and OTP results. The recommended target gives each
Jido failure a stable class and code, normalizes callback and runtime faults at
public boundaries, and keeps a small registry of protocol control values. It
also defines one safe projection and one recursive portable-value rule. All
target decisions are pending approval.

## Why this seam exists

- Owner: `Jido.Error` and the cross-system public-contract policy.
- Owns: error classes, stable codes, boundary normalization, safe projection,
  protocol exceptions, and portable-value rules.
- Does not own: operation state machines, Agent identity fields, persistence
  lifecycle, Plugin authority, or Telemetry event schemas.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Errors | Five classes and six Jido error structs; no common code | Seven classes, owner-defined errors, and stable codes |
| Results | Defined errors and raw failure terms coexist | Tagged failures contain a composed Splode error, except registered protocols |
| Projection | `to_map/1` returns bounded `type`, `message`, `details`, and `retryable?` | A versioned move to bounded class, type, code, message, retry, operation, and identifiers |
| Portability | Persistence checks complete records | Value owners check portable data before acceptance; persistence checks again |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No stable code registry | Callers use messages and raw terms | Stable codes with one owner and meaning | 12 and operation owners |
| Uneven normalization | Equivalent faults have different public shapes | One boundary matrix for returns, raises, throws, exits, timeouts, and task failures | 12, 01, 05, 07, 08, 09 |
| Projection conflict | A direct replacement can break telemetry and callers | Versioned projection with bounded fields and migration proof | 12 and 13 |
| Late portability checks | Nonportable state can exist before persistence | Path-aware checks at each owned acceptance boundary | 01, 05, 07, 12 |

## Decisions requested

1. **Taxonomy:** Approve the seven error classes and package ownership rules.
   Effect: each public failure has one stable class.
2. **Codes and normalization:** Approve stable owner-defined codes and one
   normalization matrix. Effect: callers do not inspect messages or raw terms.
3. **Projection migration:** Approve a versioned projection and keep the current
   four-key form during migration. Effect: observation consumers can move safely.
4. **Protocol controls:** Approve a closed registry for Map-like, OTP, and
   adapter controls. Effect: a raw value cannot appear by accident.
5. **Portable values:** Approve recursive, path-aware validation before an
   Agent or Plugin state value becomes valid. Effect: failure occurs before
   commit, with persistence checks kept as defense in depth.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/README.md) and
  [90 Package boundaries](../90_package-boundaries/README.md), both used as
  pending draft prerequisites.
- Dependents: 01 Agent, 05 Plugins, 07 Persistence, 08 Agent Server, 09 Jido
  instance, 13 Observability, and 99 Delivery.
- Blockers: Both prerequisites and all decisions in this seam are pending
  approval. Operation owners must confirm their final failure meanings.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
