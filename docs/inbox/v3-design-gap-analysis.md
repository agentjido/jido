# V3 design gap analysis and planning restart

Date: 2026-09-08

## Purpose

This document records a comparison between the aspirational documents in
`docs/design` and the current code in `lib`. The code is the source of truth.
The goal is to recover useful V3 planning ideas without treating old removal
proposals as current decisions.

## Summary

The current code is a strong local V3 runtime. The design folder is not one
active plan. It contains three kinds of material:

1. Implemented contracts and implementation notes.
2. Deferred replacement designs.
3. New plans that change or refine an older proposal.

The safe direction is to keep the current supported API as the baseline and
add selected V3 contracts in dependency order. A new decision and migration
plan must exist before a supported API is removed.

## Current implemented baseline

The current code supports:

- Immutable Agent definitions and instances.
- Spark DSL, inline Actions, Builder, and Codec authoring.
- Direct Agent evaluation and live Agent Server commits.
- Public PID-based Agent Server operations.
- Plugin-owned state, admission, preparation, Directives, and runtime children.
- Portable checkpoints and binary persistence with atomic compare-and-swap.
- State versions and commit-before-Directive order.
- Recoverable work through saved Plugin state.
- Local and remote owned children.
- Stable scheduled occurrence IDs and retry controls.
- Static Topology plans, local activation, readiness, and manual repair.
- Basic semantic telemetry and Turn outcomes.

The `guides/core-scope.md` guide correctly describes this baseline.

## Executable gap evidence

The research suite currently reports 34 passing tests and 11 skipped tests.
The skips are acceptable research gaps. Their retained assertions define these
missing contracts:

| Area | Missing contract |
| --- | --- |
| Routing | Select the first Signal Router match by precedence. |
| Routing | Select the executable from the source Signal before Plugin preparation. |
| Plugin data | Limit the Agent fields that each Plugin can observe. |
| Plugin data | Give each Plugin an isolated prepared input. |
| Plugin runtime | Build replacement Init from current committed Plugin state and state version. |
| Identity | Use one stable namespace, partition, and Agent ID across runtime and persistence. |
| Definitions | Save and check a positive definition revision. |
| Persistence | Use durable tombstones so a stale writer cannot recreate a deleted Agent. |
| Turn upgrade | Keep one executable revision for the complete active Turn. |
| State upgrade | Install a definition and migrate domain and Plugin state in one commit. |
| Topology upgrade | Apply a live target while unchanged members retain PID and state. |

These are known missing contracts. They are not regressions against the
currently supported API.

## Additional design-only gaps

These proposed items do not yet have complete acceptance proof:

- The proposed `Agent.Ref`, `Agent.Checkpoint`, `Agent.Commit`,
  `Persistence.Record`, runtime status, and instance configuration structs do
  not exist.
- Persistent creation does not have the full runtime-ready, initial-write,
  then-publish contract.
- Only uncertain persistence errors always stop the Server. The proposal says
  that every write error removes write authority.
- Deletion uses adapter deletion instead of a compare-and-swap tombstone.
- There is no independent `turn_timeout` contract.
- The Jido supervisor uses `:one_for_one`. Plugin wrappers and Agent Servers
  also share the Agent supervisor instead of separate runtime pools.
- Error support has basic Splode classes, but it does not have the proposed
  Persistence and Runtime errors with stable codes.
- OBS-01 is present. Persistence events, admission events, the full metric set,
  and retirement of the old debug and tracer paths are not complete.
- The combined Topology authoring host exists. The owner runtime,
  `start_topology`, committed desired state, and live target updates do not.
- Upgrade cases UP-03 through UP-06 and UP-08 through UP-10 need executable
  probes.

## Old proposals that must not return without a new decision

The following old design instructions conflict with the current source of
truth:

- Remove Builder and Codec.
- Remove neutral Agent definitions.
- Require module-only authoring.
- Remove public PID-based Agent Server operations immediately.
- Remove logical child ownership.
- Remove local debug support immediately.

These are currently supported parts of Jido. Definition revisions can be
added without removing Builder or Codec. A Ref-first facade can be added
before the PID API is deprecated. Each removal needs an explicit product
decision, compatibility period, and migration evidence.

## Plugin facet direction

A Plugin facet proposal was present during the review, but it is not in the
current design tree. Keep it as an outstanding concept until the planning
cycle makes an explicit decision. The proposal identifies that the current
`Jido.Plugin` behavior mixes pure Agent work with live Agent Server work.

Its staged plan is safer than an immediate Plugin replacement:

1. Record current callback order and failure behavior.
2. Add a neutral manifest and owner-specific Specs.
3. Extract the Agent facet.
4. Extract the Agent Server facet.
5. Convert built-in Plugins.
6. Add Persistence and Topology facets.
7. Migrate public packages through a compatibility period.

One decision must come first: define how complete custom Agent checkpoint
callbacks interact with Plugin-owned persistence conversion.

The Plugin facet plan must also absorb the proven isolation gaps. It must not
leave prepared input as one shared mutable value, and runtime replacement must
receive current committed Plugin state and state version.

## Recommended planning order

### 1. Confirm the retained baseline

Keep the DSL, Builder, Codec, owned children, current persistence adapters,
and PID API during migration. Convert the design folder from one implied target
into clear current, proposed, superseded, and deferred sections.

### 2. Close the Turn boundary

Implement route precedence and fixed executable selection. These gaps are
small, well defined, and have retained acceptance assertions.

### 3. Start the Plugin facet migration

Add characterization tests first. Then add Agent and Agent Server facets.
Include prepared-input isolation, observed-field limits, and fresh runtime Init
in this work.

### 4. Add stable identity and definition revision

Add namespace-based Agent Ref and revision checks without removing current
authoring forms. Builder and Codec output must resolve to the same validated
definition contract.

### 5. Harden persistence

Add Commit and Record values, initial durable creation, tombstones, and loss of
write authority after every write error. Keep compare-and-swap as the adapter
foundation.

### 6. Add explicit upgrade operations

First solve Turn revision stability. Then add atomic definition and state
migration. Define admission, pending work, runtime replacement, and recovery
rules before a public upgrade API is called complete.

### 7. Complete the Topology owner runtime

Store desired topology state in the owner Agent. Add live target updates only
after this authority boundary exists. Add rolling and resumable upgrades after
basic live replacement is proven.

### 8. Keep larger systems outside core

- Recovery scans, leases, fencing, and storage maintenance belong in a durable
  package.
- Membership, placement, rebalance, and failover belong in a cluster package.
- Transport gateways and durable inboxes belong in a fabric package.

Add a small core API only when an extension otherwise must use private Server
state, private messages, or generated runtime names.

## Dependency order

The main dependencies are:

```text
fixed Turn boundary
  -> Plugin isolation and owner facets
  -> fresh runtime Init

stable Agent Ref
  -> durable Record identity
  -> tombstone deletion and write authority

definition revision
  -> Turn revision boundary
  -> definition and state migration
  -> durable upgrade recovery

Topology owner runtime
  -> live target update
  -> rolling and resumable topology upgrade
```

## Documentation drift

The old feature and live-upgrade result documents say that the 11 research
assertions are enabled failures. The current tests mark them as skipped. The
assertions remain useful, but the saved result text is no longer the current
test status. `guides/core-scope.md` has the correct status.

The design folder should eventually use a simple status on each contract:

- Implemented and supported.
- Proposed and accepted for planning.
- Proposed and pending a decision.
- Superseded.
- Deferred to another package.

This status should apply to individual contracts, not only to a complete
document. Several documents contain both implemented and deferred material.

## Planning start point

The first deeper alignment cycle should make these decisions:

1. Which current public APIs are retained for V3 release?
2. Is the four-facet Plugin model the target architecture?
3. How do custom checkpoints interact with Persistence facets?
4. Is stable Agent Ref part of core V3, or a later compatibility addition?
5. Is definition revision required for all authoring forms?
6. Which persistence guarantees are required for V3 release?
7. Are live Agent and Topology upgrades release requirements or later work?
8. Which observability work is required before V3 release?

After these decisions, the existing research assertions can become ordered
acceptance gates instead of one undifferentiated gap list.

## Foundation verification

The planning cycle starts from this verified local foundation:

- Branch: `v3-spike`.
- `jido_action` branch: clean `release/v3` at `c0122f7`.
- `mix quality`: 1,090 tests passed and 1 approved test was excluded.
- `mix examples --seed 0`: 283 tests passed and 11 research tests were
  skipped.
- `mix docs --warnings-as-errors`: passed.
- Factory and Topology controller integration modules run serially so that
  scheduler load is not an input to their fixed mailbox timeouts.
- The current `jido_action` dependency uses the sibling checkout for this
  cross-package integration cycle.
