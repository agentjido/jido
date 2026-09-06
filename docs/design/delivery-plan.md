> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Delivery plan

[Design overview](README.md)

This is the deferred implementation sequence for the earlier target design.
It is not the active work plan for `v3-spike`. Several items differ from the
implemented API or are already partly implemented. Check the
[core scope guide](../../guides/core-scope.md) before using this sequence.

The current refinement retains Builder, Codec, logical child ownership, and
the public Agent Server API. It adds Scheduler delivery timing and explicit
Topology repair requests. The removal items below require a separate scope
decision and acceptance evidence.

## Proposed implementation sequence

1. Add the public value structs in the overview, their Zoi schemas, and the
   defined Splode errors.
2. Add the recursive portable-term validator and apply it to Agent state,
   Plugin state, prepared Plugin input, checkpoints, and explicit durable work.
   Runtime Directive fields follow their own contracts.
3. Implement the one versioned Agent module authoring path and generated
   constructors. Do not add Builder or Codec systems to core.
4. Implement Plugin identity, owned state, observed state fields, isolated
   preparation input, bounded Transition views, and contribution validation.
5. Implement the private Turn Evaluator with route selection before Plugin
   preparation and one protected executable output.
6. Implement the Ref-first instance facade and keep Agent Server functions and
   messages internal.
7. Add the internal `:gen_statem` Server, evaluation cancellation and timeout,
   non-cancellable commit, closed error policy, and stale task-result checks.
8. Add compare-and-swap persistence, readiness-before-create, and
   lost-write-authority handling. Prove explicit durable work through Plugin
   state, supervised retry, and completion Signals. REC-01 needs no core outbox.
9. Add Plugin runtime hosts. Make each activation and replacement use a fresh
   Init from committed Plugin state and version.
10. Add only semantic core telemetry. Keep debug timelines and internal-stage
    events outside Agent Server state and outside the stable core API.

## Agent and authoring tests

- Every Agent module has a positive definition revision.
- Module and generated constructors return equal complete Agents.
- Instance options cannot replace static module configuration.
- Construction, state replacement, candidate validation, checkpoint, and
  restore enforce the portable-term contract.
- Checkpoint restore requires the exact saved module and definition revision.
- Core exposes no Builder, Agent Codec, Plugin Codec, authoring Registry,
  complete-Agent Map constructor, or neutral Agent definition.
- Direct `Agent.cmd/3` returns a candidate evaluation value and does not claim
  a live or durable Result.

## Route and Plugin tests

- Route precedence uses exact, `*`, `**`, complexity, priority, and declaration
  order.
- Route selection uses the source Signal before Plugin preparation.
- Preparation cannot change the executable, route parameters, source Signal,
  or assigned Plugin ID.
- A prepared effective Signal does not cause a second route lookup.
- Each Plugin can return only its own prepared input.
- A later Plugin cannot read or replace an earlier Plugin's input.
- `Jido.Exec` receives the complete read-only Plugin input Map.
- Agent construction rejects an observed state field that is not in the Agent
  state schema.
- A Plugin Transition contains only declared state fields, owned Turn
  Directives, Signal identities, and Signal type.
- A contribution cannot read another Plugin's Transition or contribution.
- A contribution can replace only its complete owned Plugin state and add only
  its owned Directives.
- Preparation and contribution remain serial and follow Plugin declaration
  order.
- Invalid callback returns, raises, throws, exits, and schema failures produce
  no candidate.

## Agent Server and API tests

- The Jido instance facade is the only supported live command and inspection
  API.
- Agent Server PID-based commands and private messages are not public.
- `cast/3` is a best-effort send and gives no admission, execution, or commit
  acknowledgement.
- `call/3` and `send_request/3` admission deadlines are separate from
  `turn_timeout`.
- A caller wait timeout does not cancel active evaluation.
- A finite Turn timeout starts with evaluation, terminates its task, keeps the
  committed Agent, and rejects a late result.
- Cancellation succeeds only in `:evaluate`. No active Turn, a mismatched Turn
  ID, and a request after the commit boundary have distinct errors.
- Cancellation and task-result races follow `:gen_statem` event order once.
- Commit and Directive work cannot be cancelled.
- The error policy accepts only `:continue` or `:stop` and runs no application
  function.
- Direct evaluation and live evaluation produce the same candidate and
  Directive list before commit.
- Public status uses `%Jido.Agent.Status{}` and
  `%Jido.Agent.Turn.Status{}`.

## Persistence and effect tests

- Persistent creation completes Plugin readiness before the first active
  Record write.
- Readiness failure stops provisional runtimes, releases the local reservation,
  and leaves no Record.
- An initial write error stops provisional runtimes. An indeterminate result
  requires explicit activation.
- A new Agent state Commit has `state_version == old_version + 1` and does not
  store a duplicate prior state version.
- Record `storage_version` is the compare-and-swap concurrency guard.
- Every persistence write error keeps prior live state, starts no new
  Directive, and stops the Server with lost write authority.
- A persistence timeout is indeterminate.
- A later activation loads the authoritative Record after lost authority.
- Explicit work intent commits in Agent or Plugin state with the business change.
- A supervised worker reads pending state after restart and lost wake-ups.
- Completion uses a new Signal and advances the normal Agent revision.
- Later business Turns preserve pending work without a universal admission gate.
- Failed delivery retains pending intent and applies the capability retry policy.
- Duplicate delivery uses the same application work ID and defined receiver policy.

## Runtime topology tests

- Agent Servers are direct peers under `AgentPool`.
- Core starts no relationship store and exposes no relationship type, API, or
  relationship Directive.
- Cross-Agent Signal delivery resolves the current PID from Agent Ref.
- A persistent Server restart loads the latest durable Record.
- A nonpersistent Server restart resets to the exact initial Agent and version
  zero.
- A Plugin runtime host lives only in `PluginRuntimePool`.
- The first persistent runtime Init uses provisional initial state at version
  zero.
- Activation and every runtime replacement use the latest committed Plugin
  state and version.
- A host cannot restart a root with a captured old Init.
- Runtime Status reports the state version used by the root.
- Plugin runtimes send Signals only through the Ref-first instance facade.

## Error and observability tests

- Command, construction, and lifecycle failures return a defined error accepted
  by the composed Splode.
- Raw Map and OTP control values occur only at the explicit protocol exceptions
  listed in the error design.
- Provider control atoms normalize before they enter a semantic result.
- Core telemetry exposes only lifecycle, Turn, Commit, persistence, Directive,
  admission rejection, and Turn settlement boundaries.
- Internal evaluation stages create no stable core event names.
- Agent state, Plugin state, Signals, Directives, and runtime Context values do
  not enter telemetry metadata.
- Direct `Agent.cmd/3` emits no telemetry.
- A telemetry handler failure cannot change a Result.
- Agent Server state contains no debug or observation buffer.

Use pure tests first. Use eventual assertions for asynchronous runtime tests.
Do not use `Process.sleep/1` for synchronization.

## Deferred package designs

- External Agent Builder, Codec, editor, and trusted document Registry.
- Logical Agent relationship and orchestration policy.
- Durable Agent catalog and automatic activation.
- Checkpoint migration.
- Cluster-wide ownership authority, automatic placement, and external transport.
  Core explicit node targeting for owned children is covered by
  [remote owned children](remote-owned-children.md).
- External telemetry timelines and durable audit history.
