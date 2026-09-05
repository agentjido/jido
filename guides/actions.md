# Actions and Flows

Route a Signal to one `Jido.Action` or `Jido.Flow`. The selected executable
receives Signal data as input. It receives current state in `context.agent_state`,
and identity and Signal in `context.agent_id` and `context.signal`.
These context keys are reserved.

Return `{:ok, complete_state}` or `{:ok, complete_state, directives}`.
Return `{:error, reason}` on failure. A partial map is not a state patch.
Use the current state as the base when a field must remain unchanged.

Actions and Flows can perform I/O before commit. A later validation or storage
failure does not undo that I/O. Use stable operation IDs and application
idempotency where repetition can change an external result.

The pinned `jido_action` beta.6 provides Flow composition and inline Actions.
See the [Workflow catalog](../lib/examples/02_workflow/README.md).
