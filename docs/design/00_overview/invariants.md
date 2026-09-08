> Cross-system design proposal. This document is pending approval.

# Cross-system invariants

These invariants span more than one subsystem. Each owning subsystem must link
to the invariant that it implements.

## Turn and Plugin boundaries

- The Agent path works with no Plugins.
- Agent route resolution selects the first match in Signal Router precedence
  order.
- Route resolution uses the original source Signal and completes before Plugin
  preparation.
- Plugin preparation cannot replace the selected executable or cause another
  route lookup.
- Direct `Agent.cmd/3` and live Server execution use the same Turn Evaluator.
- During a command, the Action or Flow is the only writer of domain state.
- Plugin callbacks cannot read or change the complete executable output.
- Each Plugin owns at most one complete Plugin state entry.
- Each Plugin can replace only its complete owned state entry.
- Each Plugin receives only its declared state fields, owned Turn Directives,
  and owned prepared input.
- Plugin preparation and contribution run serially in declaration order.
- Only Jido assembles the candidate Agent.

## Commit, persistence, and recovery

- Live Agent state has one commit point.
- Each Agent state Commit increments the state version by one.
- Runtime effects start after commit.
- Explicit durable work stores portable intent and stable IDs with the business
  change in one checkpoint.
- A supervised capability worker resumes pending work after startup.
- Completion enters through a new Signal and normal Agent commit.
- Later Turns preserve pending work. Core has no universal durable outbox gate.
- Ordinary Directive dispatch does not promise crash recovery.
- Persistence updates use compare-and-swap storage versions.
- Only a confirmed successful persistence write lets the current Server keep
  write authority.
- A persistence write error stops the current Server under the proposed
  lost-write-authority contract.
- Normal durable deletion writes a tombstone.

## Definition, identity, and lifecycle

- Every Agent uses a positive module-owned definition revision under the
  proposed revision contract.
- Restore requires the saved module and revision to match the current
  definition.
- Registry, persistence, and Directives use the same Agent Ref.
- A PID is not durable Agent identity.
- Persistent Server restart loads the latest durable Record.
- Nonpersistent Server restart uses its preserved initial Agent at state
  version zero.
- Persistence I/O crosses only the owning Jido instance boundary.
- Persistent creation makes provisional Plugin runtimes ready before it writes
  the initial active Record.

## Runtime boundaries

- Every Agent Server is a peer in the Agent pool.
- Plugin runtime hosts do not live in the Agent pool.
- Runtime replacement uses current committed Plugin state and Agent state
  version.
- Runtime handles and executable workflow state never enter Agent state or
  checkpoints.
- Only pre-commit evaluation is cancellable.
- Commit and Directive dispatch are not cancellable.
- Turn timeout is independent from caller request timeout.
- Plugin runtimes send state changes through Signals and the Agent mailbox.

## Public values, errors, and observation

- Portable Agent state, Plugin state, and saved work contain no PID, port,
  reference, function, improper list, or non-byte-aligned bitstring.
- Each shaped public success value has one documented owner and purpose.
- Command, construction, and lifecycle failures use defined Splode errors.
- Raw Map and OTP control values are explicit documented protocol exceptions.
- Direct `Agent.cmd/3` emits no runtime telemetry.
- The live Turn result span stops at the commit and result boundary.
- Directive work uses separate post-commit spans.
- Observation cannot change an Agent result or runtime outcome.
- Telemetry metadata contains no Agent state, Plugin state, or payloads.
