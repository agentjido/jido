> The commit contract is implemented. Its owned-work refinement is pending
> approval.

# 06 — Commit and effects

## Briefing

Jido has one live commit sequence:

```text
validated candidate and Directive batch
  -> required checkpoint write
  -> replace the complete live Agent and advance the version once
  -> confirm commit to the caller
  -> handle Directives in returned order
  -> settle the Turn
```

A successful `Jido.AgentServer.call/3` confirms the commit. It does not confirm
Directive settlement or external business completion. A pre-commit failure
keeps the prior Agent and version. External Action or Flow work that completed
before that failure is outside the rollback boundary. A post-commit Directive
failure keeps the new commit and stops the remaining batch.

Every required persistence write error now stops that Server activation before
it can evaluate more work. A confirmed conflict did not replace storage. An
indeterminate result can mean that storage changed but the reply was lost. In
both cases, a new activation must restore authoritative state.

Ordinary Directive batches are transient. Jido does not replay them after
Server loss, and a timeout does not prove that an external effect did not
occur. Recoverable work stays capability-owned: save portable intent with the
business state, use stable work IDs, and commit acknowledgement through a new
Signal and Turn. Core does not provide a universal outbox or exactly-once
external effects.

The proposed Agent Server refinement moves blocking checkpoint, persistence,
and post-commit operations into owned workers. A worker returns a fenced
receipt or result. Only the private Agent Server Runtime can accept it, publish
the candidate, reply, advance a Directive, change a relationship, or settle a
Turn. The commit order and public result meanings do not change.

## Current state

- Complete candidate validation, checkpoint, replacement, reply, Directive,
  and settlement order is implemented.
- Three-entry successful Directive order, retained external Action I/O,
  effect-before-timeout uncertainty, and ordinary-batch non-replay have focused
  tests.
- Confirmed conflicts and indeterminate writes both remove activation write
  authority. Recoverable-effect and Scheduler tests restore saved intent in a
  new activation.
- Custom checkpoint preservation is implemented in seam 07.
- Initial revision-zero durability is implemented across seams 07 and 08.
- Storage and post-commit worker receipts are proposed and are not implemented.
- Public observation of settlement interrupted by process loss is owner work
  for seam 13.

## Dependencies

- Implemented prerequisites: seams 90, 12, 01, 03, 04, and 05.
- Owner integrations: seam 07 for persistence records and checkpoint
  composition, seam 08 for startup and activation mechanics, and seam 13 for
  public settlement observation.
- Other dependents: capability packages and seam 99 delivery evidence.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
