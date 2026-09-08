# Overview alignment review briefing

> Review document. This document is pending approval. Code in `lib`, public
> module documentation, and executable tests define current behavior.

## Outcome

The recommended V3 architecture keeps the implemented local runtime as its
base. It keeps Agent values, direct evaluation, Agent Server commit rules,
Builder, Codec, owned children, public PID APIs, persistence adapters, static
Topology, and current observation paths. It adds selected contracts in
dependency order. The main changes are source-Signal route selection, Plugin
input isolation, stable Agent identity, definition revision, stronger durable
lifecycle rules, and coherent Plugin runtime replacement. The plan does not
approve detailed later-seam APIs. See the [detailed alignment
plan](alignment.md).

## Current architecture

- An Agent is an immutable definition or instance. Direct `Agent.cmd/3`
  returns a candidate Agent and Directives. It does not commit live state.
- Plugin preparation runs before routing. It can change the Signal. Jido
  requires exactly one route match, although the Signal Router returns ordered
  matches.
- One Agent Server serializes admission, evaluation, commit, and Directive
  handling. Each successful Turn increments `state_version` once.
- Actions and Flows can perform I/O before commit. Directive work starts after
  commit. A Directive failure does not undo the commit.
- Persistence stores private map records through a binary adapter and atomic
  compare-and-swap. Delete removes the record. There is no tombstone.
- A nonpersistent Server in a named Jido instance restores its last in-instance
  runtime checkpoint after an abnormal restart.
- Plugin runtime wrappers and Agent Servers use the same Agent Dynamic
  Supervisor. Runtime handles remain outside Agent state and checkpoints.
- Static local Topology activation and repair exist. Semantic telemetry exists
  beside older Agent Server telemetry, tracer, and debug paths.

## Recommended V3 architecture

- Preserve the source Signal. Select the first Router match by precedence
  before Plugin preparation. Fix one executable for the Turn.
- Keep direct and live candidate evaluation on one shared boundary. Only the
  live Agent Server can commit the candidate.
- Keep separate write owners for domain state and Plugin state. Give each
  Plugin a declared Agent view and isolated prepared input.
- Keep one commit point. A durable write must succeed before live state changes
  or Directive work starts.
- Add stable Agent identity and definition revision through staged migration.
  Keep current ID and PID APIs during that migration.
- Add an initial active persistence record, remove write authority after every
  write error, and use tombstones for normal durable deletion.
- Treat Plugin runtimes as capability resources, not Agent peers. Give each
  replacement current committed Plugin state and its matching state version.
- Keep core local. Keep static Topology and current observation APIs. Defer live
  topology control, cluster policy, and legacy API removal until their owners
  define and prove them.

## Top conflicts and recommended disposition

| Conflict | Recommendation | Later owner |
| --- | --- | --- |
| Routing occurs after Plugin preparation and rejects multiple matches. | Change to source-Signal, first-match selection. | 04 and 05 |
| Plugins see the complete Agent and share one prepared command. | Add declared views and isolated input. | 01, 04, and 05 |
| Design says nonpersistent restart resets to the initial Agent. | Remove that proposal. Keep last in-instance checkpoint restore. | 08, 09, and 10 |
| Design says all runtime effects start after commit. | Limit the rule to Directive work. | 06 |
| Stable Ref and definition revision do not exist. | Add both in compatible stages. | 01, 02, 03, 04, 07, and 09 |
| Confirmed write errors can leave a writable Server alive. | Remove write authority after every write error. | 07 and 08 |
| Persistent startup has no initial record and delete has no tombstone. | Add both durable lifecycle boundaries. | 07, 08, and 10 |
| Proposed public structs do not exist. | Approve roles only. Defer exact shapes to their owners. | 90, 12, and value owners |
| Plugin facets are a proposal. | Approve the four ownership categories, then design a staged migration. | 05 |
| Topology owner runtime and live updates do not exist. | Keep the current Controller. Defer live control. | 11 |
| Old plans remove Builder, Codec, PID APIs, or debug paths. | Remove immediate-removal instructions. Keep compatibility. | 01, 02, 08, 09, and 13 |

## Dependency and sequencing summary

First approve this overview. Then align package boundaries in seam 90 and
public errors and value rules in seam 12. Next align Agent, authoring, identity,
and Turn behavior in seams 01 through 04. Plugin ownership in seam 05 depends
on the Turn boundary. Commit and effects in seam 06 then set the input for
persistence in seam 07. Agent Server, Jido instance, and runtime topology follow
in seams 08 through 10. Topology control plane and observation follow in seams
11 and 13. Seam 99 closes release scope and migration.

Do documentation alignment before runtime changes in each phase. Keep supported
APIs until the new contract has compatibility and acceptance proof.

## Decisions requested from the user

1. Approve first-match route selection from the source Signal before Plugin
   preparation.
2. Approve the current last-commit runtime checkpoint as the nonpersistent
   abnormal-restart rule.
3. Approve stable Agent Ref as a V3 core target, with current PID APIs kept
   during migration.
4. Approve a positive module-owned definition revision, with Builder and Codec
   support and a legacy checkpoint rule.
5. Approve Agent, Agent Server, Persistence, and Topology as the four proposed
   Plugin facet owners. Keep one ordered Plugin declaration.
6. Keep complete custom Agent checkpoint callbacks until seams 01, 05, and 07
   define safe composition with Persistence facets.
7. Require initial active records, write-authority loss after every write
   error, and tombstones for V3 durability.
8. Retain Builder, Codec, neutral definitions, owned children, public PID APIs,
   and local debug paths for the V3 release.
9. Keep static local Topology in V3. Defer owner-Agent live control and live
   target updates.
10. Keep Jido core local. Defer general durable, cluster, and fabric services
    to focused packages.
11. Approve public value roles, but defer exact new structs to seam 90, seam 12,
    and each value owner.
12. Keep legacy telemetry, tracer, and debug paths while semantic event coverage
    becomes complete.

## Main risks if decisions remain open

- Seams 01 through 05 can define incompatible Signal, Turn, and Plugin inputs.
- Identity, persistence keys, PID APIs, and topology placement can require two
  migrations instead of one.
- Restore can accept state under the wrong definition, while a false claim of
  code pinning can hide live-upgrade risk.
- A stale persistent activation can continue after a confirmed write failure,
  or a delayed writer can recreate a deleted Agent.
- Runtime topology can separate pools before restart and readiness rules are
  known.
- Later documents can remove supported APIs without a compatibility period.
- Live Topology and package work can delay V3 without an approved release
  boundary.
