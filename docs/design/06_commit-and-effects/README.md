> Seam review entry point. This document is pending approval.

# 06 — Commit and effects

## Briefing

Jido already has one strong live commit boundary. Turn evaluation returns one
validated candidate Agent and an ordered Directive list. The Agent Server then
validates live batch policy, saves a runtime checkpoint or durable record,
replaces the authoritative Agent and state version once, replies to a
synchronous caller, and handles Directives in list order. A pre-commit failure
keeps the prior live snapshot. A post-commit Directive failure does not undo the
commit. The recommended target keeps this model, states that commit replaces a
complete immutable snapshot, preserves source and causation data through
post-commit work, and keeps recoverable work an explicit capability instead of
a universal Directive outbox.

The target also closes four contract gaps: custom checkpoints must preserve
state used by a durability claim; ordinary Directive crashes and timeouts have
an explicit uncertainty meaning; a successful call confirms commit but not
settlement or external completion; and persistence write errors use one
approved write-authority rule. All target requirements remain pending approval.

## Why this seam exists

- Owner: the Jido live commit semantic boundary.
- Owns: the change from one validated candidate to one authoritative Agent
  snapshot, revision advancement, pre-commit and post-commit failure meaning,
  and the boundary between transient Directives and explicit recoverable work.
- Does not own: candidate evaluation, Plugin callback shapes, Agent Server
  admission and process mechanics, persistence record layout or adapter
  durability, Signal envelope semantics, durable workflow orchestration, or
  external receiver policy.

## Current and target state

| Area | Canonical current state | Recommended target |
| --- | --- | --- |
| Candidate boundary | Direct and live paths share the Runner. Direct `cmd/3` returns a candidate and Directives without commit or dispatch. | Keep evaluation separate from one effect-free live commit step. |
| State change | The Server replaces its complete live Agent and increments `state_version` once, including for equal state. | Define replacement, not in-place mutation, as the only live Agent commit meaning. |
| Validation | Runner validation and live Directive batch checks finish before persistence. | Keep complete candidate, Directive, ownership, limit, terminal-position, and dispatch validation before commit. |
| Persistence | A runtime checkpoint or configured compare-and-swap write finishes before live replacement. | Keep write-before-visibility; align all write failures with one write-authority rule. |
| Reply and settlement | `call/3` replies at commit. The Server remains busy until Directives stop and an Outcome is created. | State that success confirms commit only. Keep settlement as a runtime and observation boundary, with no new wait API in this seam. |
| Directive handling | Directives run in list order after commit. First failure stops the batch; later entries are skipped. | Keep order, fail-fast settlement, and no rollback. Define timeout and crash results as uncertain external-effect states. |
| Causation | Runtime Signal Directives derive causation from the effective Signal. Directive contexts and Outcomes carry source and effective Signals plus Turn ID. | Preserve those values through settlement. Do not persist transient Turn context automatically. |
| Recoverable work | Core components permit saved Plugin intent. REC-01 proves one example pattern, not a shipped general capability. | Keep capability-owned intent, stable IDs, acknowledgement, retry, and duplicate policy. Keep a universal outbox out of core. |
| Checkpoints | The default checkpoint includes combined Agent and Plugin state. Custom callbacks can omit fields. | Require every custom checkpoint used for a durability claim to preserve the required owned state and causal data. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Write-authority conflict | Current known no-write failures can leave the Server active, but the prerequisite target removes authority after every write error. | One failure rule shared by commit, Persistence, and Agent Server contracts. | 06, 07 Persistence, 08 Agent Server |
| Revision-zero durability | A new persistent Agent can become ready before its first durable record exists. | A proved initial active-record boundary before broad restore claims. | 07 Persistence, 08 Agent Server |
| Custom checkpoint omission | A callback can omit Plugin intent while documentation claims recovery. | A tested preservation duty for every state field required by a durability claim. | 01 Agent, 05 Plugins, 06 |
| Ordinary Directive interruption | A Server crash loses the transient batch and can prevent a terminal Outcome. | Explicit non-replay and settlement-uncertainty behavior with focused evidence. | 06, 08 Agent Server, 13 Observability |
| Delivery capability scope | The recoverable delivery implementation is an example. | Keep core guarantees narrow or publish a separate capability with its own contract. | 05 Plugins, capability owner |

## Decisions requested

1. **Commit meaning:** Approve complete immutable Agent replacement plus one
   revision increment as the only live state commit.
2. **Caller result:** Approve `AgentServer.call/3` success as commit
   confirmation only. Do not add a public settlement wait API in this seam.
3. **Directive uncertainty:** Approve non-replay after Server loss and state
   that a timeout does not prove that an external effect did not occur.
4. **Write authority:** Approve removal of write authority after every required
   persistence write error, as proposed by the Overview, or change the
   prerequisite to retain the current known-error and uncertain-error split.
5. **Recoverable work:** Keep the universal Directive outbox removed. Require
   an explicit capability to own portable intent, stable work IDs,
   acknowledgement, retry, ordering, cancellation, retention, and duplicates.
6. **Custom checkpoints:** Require custom callbacks to preserve all state and
   causal data used by each declared durability guarantee.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md), and
  [05 Plugins](../05_plugins/alignment.md). All are pending draft
  prerequisites.
- Related inputs: [02 Agent authoring](../02_agent-authoring/design.md) keeps
  commit outside authoring. [03 Agent identity](../03_agent-identity/design.md)
  keeps identity, location, state version, and write authority separate.
- Dependents: 07 Persistence, 08 Agent Server, 13 Observability, and 99
  Delivery.
- Blockers: prerequisite approval; the write-authority decision; the exact
  public error mapping; custom-checkpoint composition; and later-seam decisions
  for interrupted settlement and revision-zero creation.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
