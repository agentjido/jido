# Jido usage rules

Use the implemented V3 Agent contract. A definition has no instance identity or
state. Instantiate it before use. Send Signals to Actions or Flows.
Direct `Jido.Agent.cmd/3` returns `{:ok, candidate, directives}` or an error.
A live `AgentServer.call/3` returns `{:ok, committed_agent}` or an error.

Return complete candidate state. Actions and Flows can perform I/O before commit;
application idempotency must account for a later failure. Directives run after a
live commit. Ordinary directives do not acquire automatic crash recovery.
Declare Plugins explicitly and preserve their owned state keys and callback order.

Keep runtime PIDs and handles out of checkpoints. Use typed schemas, safe error
maps, instance and partition scope, owned children, and explicit resource cleanup.
An optional `max_state_size` bounds complete state in external term bytes.

Test direct values and live behavior. Use controlled barriers for concurrency and
failure tests. Run the full catalog and integration acceptance, not just default
`mix test`. Do not add an exclusion to hide a failure. Follow
[the migration guide](guides/migration.md) for removed V2 interfaces and storage.
