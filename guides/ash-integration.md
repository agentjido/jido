# Ash integration boundary

Use an Action or Flow to call application-owned Ash resources. Declare input and
output schemas and define external idempotency. A Jido state commit does not
roll back an earlier Ash transaction or remote operation.

The core migration supplies no Ash-specific adapter and makes no downstream
compatibility claim for one. Port existing callers to the V3 Action, Signal,
Plugin, and complete-state contracts. See [Actions](actions.md) and
[migration](migration.md).
