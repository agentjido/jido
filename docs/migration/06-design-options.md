# Optional design adoption after the source comparison

Status: deferred by the user on 2026-09-05. These work units are outside the
current migration goal. Keep them as a separate backlog. Do not insert them
into M02 or any later migration commit.

The prepared source at `bf6c9fb` has Agent naming and required source fixes.
The recommended core transfer preserves that behavior. Each option below
requires further contract changes. Those changes need an
explicit contract decision and a recorded deviation from the source examples.

## F01: one portable Agent identity and fixed checkpoint model

Sources: `agent.md`, `authoring.md`, `instance-persistence.md`.
Depends on decisions D01, D02 and D05.

Proposed commits:

- `feat(agent)!: define versioned Agent identity and checkpoints`
- `refactor(authoring)!: use versioned Agent modules`

Add Zoi-backed `Jido.Agent.Ref`, `Jido.Agent.Checkpoint` and `Jido.Agent.Commit`
with the fields and invariants selected from the design. Define namespace,
partition, logical ID, module and definition revision independently from PID
and live activation. Keep the storage version separate from the state version.

Replace neutral definitions and arbitrary complete-Agent construction with the
selected module-owned constructor. Remove Builder/Codec/registry entry points
only if D01 selects this restriction. Replace overridable checkpoint/restore
callbacks with fixed validation. Require a matching definition revision and
an explicit migration path for saved state.

Preserve the scenarios in Basic, Workflow and Topology. Their constructor and
format-equivalence assertions must change if Builder/Codec moves out of core.
That is a feature/API change, not a verbatim transfer. Add tests for changed
code revisions, unknown modules, illegal overrides and nested nonportable terms.

Exit: one identity resolves consistently across construction, storage and live
lookup; wrong identity/revision fails before executable work.

## F02: protected route and Plugin composition

Sources: `turn-evaluation.md`, `plugins.md`.
Depends on D03 and the selected Agent state shape.

Proposed commit: `refactor(plugin)!: isolate preparation and state contributions`.

Add the selected public `Jido.Plugin.Command`, `Context`, `Transition` and
`Contribution` structs. Keep a private `Jido.Agent.Turn.Evaluator` shared by
direct and live commands. Select the route from the original Signal before
Plugin preparation. Enforce the selected router precedence rule.

Move Plugin state to its selected separate representation. Replace `admit`,
`state_spec`, `update_state`, `directives`, `validate_directive` and
`prepare_dispatch` only according to the reviewed callback map. Give each Plugin
an isolated input and only its declared Agent-field projection. Keep the
complete executable output private to the evaluator. Reject ownership violations,
unknown observed fields, exceptions and malformed contributions before commit.

Rewrite built-in Plugins and the example Plugins together. Preserve transformed
input, admission/authentication, audit state, ordered dispatch, recovery intent
and signed/encrypted outbound Signals. Specify where live admission and outbound
transformation move; deleting these hooks without replacements loses the
identity/secure-signal examples.

Exit: Basic Plugin/Directive cases and identity, secure-signal, subscription,
audit and recovery scenarios pass. Tests prove one Plugin cannot read or replace
another Plugin's private input or executable output.

## F03: instance-only live API

Sources: `jido-instance.md`, `agent-server.md`.
Depends on F01, D02 and D08.

Proposed commit: `refactor(runtime)!: route live operations through Agent references`.

Add validated instance options and the selected `Jido.Instance.Config`,
`Jido.Agent.Status` and `Jido.Agent.Turn.Status` values. Generate Ref-based call,
cast, request/response, cancellation, inspection and lifecycle entry points.
Make `Jido.AgentServer` internal only if that public break is selected. Retain
its established name even when its visibility changes.

Move generated example helpers to the facade. Resolve a current activation for
each logical reference; reject stale activation-dependent operations. Define
caller wait, queued admission and Turn timeout separately. Keep best-effort
cast distinct from an acknowledged commit. Preserve remote deadline corrections.

Exit: equivalent direct/live results, cancellation boundaries, stale-PID recovery,
remote calls, lost replies and inspection all pass through the selected facade.
All examples that currently pass server PIDs need a recorded interface change.

## F04: authoritative persistence records

Sources: `instance-persistence.md`, `durability-guarantee.md`,
`commit-and-effects.md`.
Depends on F01 and D05; extends M03 instead of replacing its assertions.

Proposed commit: `feat(persistence)!: commit versioned records with write authority`.

Add the selected `Jido.Persistence.Record` and instance provider callbacks.
Move from byte-adapter revision checks to the reviewed Record CAS contract.
Define creation, replacement, tombstone/delete, purge and explicit reactivation.
Start provisional runtimes and wait for readiness before the initial active
record is written. Release local reservations and provisional resources on failure.

Stop on all writes that lose authority according to the selected policy. Treat
timeouts as uncertain results. Re-read authoritative storage before a new
activation; never retry external work merely because a write reply was lost.
Specify record conversion and rollback between formats and adapter versions.

Rewrite ETS/File/Redis adapters or move them to the selected integration layer.
Keep portable work intent in the same commit as business state; completion
arrives through a new Signal. Do not introduce an implicit universal durable
outbox or claim exactly-once external effects.

Exit: all persistence probes, readiness failures, CAS races, expired/deleted
records, recovery examples and durable scheduling pass. Record tests that
previously expected a failed writer to remain live must change explicitly.

## F05: separate runtime resource supervision

Sources: `runtime-topology.md`, `runtime-extension-boundaries.md`.
Depends on D04, D07 and the selected Plugin Init contract.

Proposed commit: `refactor(runtime): separate Agent and Plugin supervision`.

Create Agent-only and Plugin-runtime pools with dependency-ordered startup.
Replace the current PluginChild wrapper with an owner-bound host that builds
fresh Init from the latest committed Plugin state and revision on each runtime
replacement. Define runtime status and dispatch context without exposing private
server state. Prove owner loss closes every resource.

If D04 removes core child relationships, move the complete ownership protocol
to the selected application/Plugin/package layer in a separate breaking commit.
Replace Spawn/Adopt/StopChild/parent signals and Topology ownership calls together.
Preserve all six Multi-agent fixtures, four Factory systems and five Topology
scenarios. Removing those scenarios is not an acceptable way to claim parity.

Exit: a runtime restart sees current committed state; hierarchy, remote lifecycle,
pending-work reconciliation and full cleanup remain correct.

## F06: semantic observation and composed errors

Sources: `observability.md`, `errors.md`.
Depends on D08 and selected identities/status structs.

Proposed commit: `refactor(observability)!: define semantic Agent outcomes and errors`.

Define the reviewed Splode classes, stable error codes and bounded identity
fields. Normalize callback/provider/OTP errors at public boundaries while
retaining declared Map and OTP control-result exceptions. Keep error transport
safe and preserve the main-branch validation-path fixes.

Publish lifecycle, admission, Turn, commit, persistence, directive and settlement
events under Agent names. If the private server timeline is removed, provide
the selected observation mechanism needed by Runtime Inspection and the demo
tools. Preserve causation and one terminal outcome per Turn.

Exit: Runtime Inspection, observation/causal-trace, Factory inspection,
observer-failure and hostile-error transport tests pass. No transient process,
payload or credential leaks through stable public error/telemetry fields.

## Ordering effect

F01 precedes F03/F04. F02 precedes the final built-in Plugin and runtime-host
rewrite. F05 follows the selected Init/state contract. F06 follows the selected
identity/status model. If several are selected, revise M02 as one coherent
replacement and retain the example acceptance stages. Do not import an old API
only to delete it immediately without a stated reason.

Cluster authority is an additional capability decision, not a consequence of
Refs, CAS or separate pools. A selected authority provider needs claim, renewal,
release and authority-loss rules plus actual partition/failure tests. Keep that
scope explicit before promising failover, singletons or sharding.
