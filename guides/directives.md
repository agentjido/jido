# Directives

An Action or Flow can return typed directives with its complete candidate state.
The Server validates the batch before commit and dispatches it after commit.
Direct execution returns the batch to the caller without dispatch.

Use the built-in `Jido.Agent.Directive` types for supported runtime operations.
Use `SpawnAgent` and `StopChild` for owned Agents. Declare other types through a
Plugin and implement its validation and dispatch callbacks. The V2
`DirectiveExec` protocol and custom `directive_handler` option are removed.

If one directive fails, the committed state remains. Later directives in that
batch do not run. Ordinary directives have no crash-replay guarantee.
Use explicit persisted intent and acknowledgement for recoverable work.

See [commit and delivery tests](../test/jido/agent/stateless_directive_test.exs)
and the [recovery examples](https://github.com/agentjido/jido/tree/v3-spike/examples/04_runtime/README.md).
