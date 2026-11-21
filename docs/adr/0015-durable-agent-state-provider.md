# Save provider-owned state and the Jido checkpoint at one commit boundary

Status: Proposed

Date: 2026-11-20

## Context

An application can maintain Agent state in a domain record with its own access
rules and type constraints. A write after an accepted Turn can fail after the
server has published success. The existing byte Store only owns checkpoint
storage and cannot validate or normalize domain fields.

## Decision

Add an optional state provider to module-defined durable Agents. It supplies
one schema. The provider owns its domain transaction and invokes a Jido
callback that prepares and saves the canonical state and the Turn receipt.
The instance still owns the checkpoint profile. AgentServer owns revision
control, lifecycle transitions, publication, and effects. Keep the provider
descriptor in executable module code. Keep snapshots and direct commands
independent of the provider's database code.

## Consequences

The provider must verify that its writes and the checkpoint can share one
transaction. A rollback gives Jido a failed Turn. An uncertain result uses
the existing durable reconciliation path. Unbound Agents continue to use the
standard checkpoint path.
