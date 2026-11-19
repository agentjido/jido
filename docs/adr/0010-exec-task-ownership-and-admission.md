# ADR 0010 — Exec task ownership and admission

**Status** Accepted

**Date** 2026-11-19

Collection items can trap linked exit signals. A component timeout or caller
exit could leave such an item running. A linked item crash could also end a
collection configured to collect errors.

Use Runic's task scope to register immediate execution tasks and concurrent
collection items. Use the same scope for nested calls. Cancel and await the
tasks in that scope. Collect-errors mode isolates each item, including at
concurrency one.

Admit one root task per immediate call through a local Task Supervisor. Use its
capacity limit to reject excess work. Tasks within an active Runic scope use
that scope's supervisor and share the admission. Keep the Runic task scope
integration in `Jido.Exec.Runtime`.

Start an optional monotonic deadline at the immediate entry point. Pass the
absolute deadline to Runic and cancel the owned task tree when the budget
expires. Use a scoped task for admission with a finite deadline so it can
stop while the host supervisor is unavailable. The component attempt
timeout remains a separate policy.

[Execution guide](../../guides/flow-runtime/execution.md)
