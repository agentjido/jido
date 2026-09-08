> Documentation template. This document is pending approval.

# Architectural seam template

Use this template for each numbered folder under `docs/design`.

## Required files

```text
<NN_seam>/
  README.md
  design.md
  alignment.md
```

Use only these three files by default:

- `README.md` is the briefing and review entry point.
- `design.md` is the target contract.
- `alignment.md` connects canonical code to the target contract.

Do not add separate `briefing.md`, `gap-analysis.md`, or `evidence.md` files.
Put that content in the sections below. Add a supporting topic document only
when it defines a large independent contract that would make `design.md`
difficult to review.

## `README.md` template

Keep this file at 1,200 words or less.

```markdown
> Seam review entry point. This document is pending approval.

# <NN> — <Seam name>

## Briefing

<One paragraph. State the current position, the recommended target, and the
main change.>

## Why this seam exists

- Owner: `<owning module or subsystem>`
- Owns: <short list>
- Does not own: <short list>

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| <contract> | <implemented fact> | <recommended result> |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| <short gap> | <effect> | <result, not implementation tasks> | <seam> |

## Decisions requested

1. **<Decision name>:** Approve <recommended option>.
   Effect: <what this decision enables or prevents>.

## Dependencies

- Prerequisites: <approved seam alignment links, or `None`>
- Dependents: <seams that use this contract>
- Blockers: <unresolved prerequisite decisions, or `None`>

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
```

## `design.md` template

This file states the planned end state. Do not put implementation history or a
phase plan here.

```markdown
> Target seam design. This document is pending approval.

# <Seam name> design

## Scope and owner

- Owner: `<module or subsystem>`
- In scope: <owned concepts>
- Out of scope: <concepts owned by other seams>

## Model

<Define values, state, boundaries, and information flow. Add one small diagram
only when it makes ownership or sequence clearer.>

## Requirements

### <Requirement group>

`<SEAM>-REQ-001`: When <trigger>, the <owner> shall <observable response>.

`<SEAM>-REQ-002`: The <owner> shall <observable response>.

## Public contract

<Define public values, functions, callbacks, errors, and compatibility rules.
Use signatures only when they make the contract clearer.>

## Invariants

- `<SEAM>-INV-001`: <condition that must always remain true>.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| <seam> | <what it can rely on> |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `<SEAM>-DEC-001` | <small decision> | <recommendation> | <effect> |
```

## `alignment.md` template

This file is the working plan. It records current evidence, gaps, and the path
to the target. Delete superseded analysis after its unique evidence is present
here.

```markdown
> Seam alignment plan. This document is pending approval.

# <Seam name> alignment

## Status

- Design reviewed: <commit or date>
- Code reviewed: <commit>
- Prerequisite alignments: <links or `None`>
- Alignment state: `Draft`, `Blocked`, `Ready`, or `Complete`

The alignment state is execution status. It is not document approval.

## Inputs and evidence

### Design

- `<path>`: <reason>

### Canonical code

- `<path:line>`: <implemented behavior>

### Tests and examples

- `<path:line>`: <behavior proved>

## Retained baseline

<List supported behavior that the plan will preserve.>

## Gap register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `<SEAM>-GAP-001` | `<SEAM>-REQ-001` | `<path:line>` | <gap> | `Retain`, `Change`, `Defer`, or `Remove` |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the implementation plan later with `ce-plan` after the design is
approved.

### Phase 0 — Resolve prerequisites

- Contract change: <decision or none>
- Compatibility: <effect>
- Verification: <test or review>
- Exit criteria: <observable result>

### Phase 1 — <Small outcome>

- Requirements: `<SEAM>-REQ-001`
- Required outcome: <result>
- Constraints: <contracts that the later implementation plan must preserve>
- Compatibility: <migration>
- Verification: <tests>
- Exit criteria: <observable result>

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `<SEAM>-REQ-001` | `<path:line>` or `None` | `<test or check>` | `Proven`, `Partial`, `Missing`, or `Conflict` |

## Migration and compatibility

<List deprecations, adapters, data migrations, release gates, and rollback
rules. State `None` when no migration is required.>

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `<SEAM>-BLK-001` | `Assumption` or `Blocker` | <seam> | <statement> | <decision or evidence> |

## Completion criteria

- [ ] All approved requirements have `Proven` evidence.
- [ ] No unresolved `Conflict` remains.
- [ ] Compatibility work is complete.
- [ ] Dependent seam documents use the approved contract.
```

## Content rules

1. Put each fact in one file only.
2. Link to detail instead of repeating it in the briefing.
3. Use `design.md` for target requirements, not current implementation notes.
4. Use `alignment.md` for current behavior, gaps, evidence, and execution order.
5. Use `README.md` for decisions and a short comparison, not full evidence.
6. Use EARS for every required target behavior.
7. Keep requirement, decision, gap, invariant, and blocker identifiers stable.
8. Treat code in `lib` and executable tests as canonical current behavior.
9. Keep every changed document at `Pending approval` until the user approves it.
10. Do not put implementation tasks in the seam documents. Use `ce-plan` after
    the seam design is approved.

## Migration from the current folders

For each seam review:

1. Move target contracts from topic documents into `design.md`.
2. Move unique code evidence and gaps into `alignment.md`.
3. Move the briefing summary and decision checklist into `README.md`.
4. Update links to use requirement and gap identifiers.
5. Remove superseded `briefing.md`, `gap-analysis.md`, and duplicate topic
   documents only after their unique content is preserved.
6. Keep Git history as the record of removed drafts and execution reports.
