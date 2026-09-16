# Directives

An Action or Flow can return typed directives with its complete candidate state.
The Server validates the batch before commit and dispatches it after commit.
Direct execution returns the batch to the caller without dispatch.

Use the built-in `Jido.Agent.Directive` types for supported runtime operations.
Use `SpawnChild` and `StopChild` for owned Agents. Use `SpawnProcess` only for
an untracked supervised OTP process. Declare other types through a Plugin Agent
facet. Put validation in that facet. Put optional post-commit dispatch in the
Plugin Agent Server facet. The V2
`DirectiveExec` protocol and custom `directive_handler` option are removed.

If one directive fails, the committed state remains. Later directives in that
batch do not run. Ordinary directives have no crash-replay guarantee.
Use explicit persisted intent and acknowledgement for recoverable work.
For `SpawnProcess`, a raised start callback, an exit, or an unexpected start
result becomes a Directive failure after commit. The external start may already
have happened; Jido cannot undo it.

See [commit and delivery tests](../test/jido/agent/stateless_directive_test.exs)
and the [recovery examples](https://github.com/agentjido/jido/blob/release/v3/examples/04_runtime/README.md).
