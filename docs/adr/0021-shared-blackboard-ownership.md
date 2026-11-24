# ADR 0021 — Give each shared blackboard one owner

- Status: Proposed
- Date: 2026-11-23

## Context

Agents in the same topology can exchange Signals. A member can need to
read a current value after it restarts. If members act on the same value,
the board must check the revision and apply each accepted update together.

## Decision

The Server Plugin starts one board under an Agent's activation. A board name
is local to a Jido instance. One process owns the values and serializes each
conditional patch. The board token includes its process generation. The
Client Plugin reads a snapshot on selected Signals and dispatches writes
after the Agent's turn commits.

An owner can use the instance persistence profile. The board owns one
versioned record identified by the owner's stable Address and the board
name. The Store atomically replaces that record on an accepted patch.
Reopening the board restores its values and changes its generation.
Explicit deletion of a stopped board replaces its record with a tombstone.

## Consequences

The configured Store controls how long a saved board survives. In-memory
boards reset on owner restart. An Agent turn and a board patch have separate
commit points. A timeout or Store fault can leave the patch outcome uncertain.
The owner discards its cached snapshot if a Store write is indeterminate.
The topology and both Plugins use the existing core lifecycle.

## References

- [Implementation plan](../plans/2026-11-23-1721-shared-blackboard-plan.md)
- [Shared blackboard guide](../../guides/built-in-plugins/shared-blackboard.md)
