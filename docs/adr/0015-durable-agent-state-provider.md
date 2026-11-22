# Coordinate state-source activation and commit in Persistence

Status: Proposed

Date: 2026-11-20

## Context

An application can maintain Agent state in a domain record with its own access
rules and type constraints. A write after an accepted Turn can fail after the
server has published success. The existing byte Store only owns checkpoint
storage and cannot validate or normalize domain fields.

## Decision

Add an optional state source to module-defined durable Agents. A Plugin
declares its schema and descriptor. Persistence uses the instance's adapter
to open the transaction for activation and successful Turn commits. The
source loads or writes domain fields inside that transaction. Persistence
selects the state to restore and saves the canonical checkpoint and Turn
receipt. A pending Turn keeps the state saved at admission.

AgentServer owns revision control, lifecycle transitions, publication, and
effects. Keep the source descriptor in executable module code. Keep
snapshots and direct commands independent of the source's database code.

## Consequences

The adapter checks that domain writes and the checkpoint can share one
transaction. A confirmed rejection fails the Turn. An uncertain result uses
the existing durable reconciliation path. Unbound Agents use the standard
checkpoint path.
