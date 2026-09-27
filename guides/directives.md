# Directives

An Action or Flow can return typed directives with its complete candidate state.
The Server validates the batch before commit and dispatches it after commit.
Direct execution returns the batch to the caller without dispatch.

Use the explicit Action result contract:

```elixir
{:ok, next_state, directives}
```

The same result survives a one-step Flow. A longer Flow collects all successful
executed steps, including the last step and unreferenced outputs. It returns
one batch with its final output. `jido_action` carries opaque values; Jido core
validates each value as an owned Directive before commit. `Jido.Agent.cmd/3` still
returns `{:ok, candidate, directives}` without dispatch.

Effects use canonical dependency order, with component name as the tie breaker.
A nested Flow contributes once at its parent position. Choice contributes only
the selected branch. Map and Reduce use item order; Iterate uses iteration order.
Dispatch keeps decision effects before normal expander effects, and a
continuation appends the next executable's effects. Worker completion order
does not change the batch. Supported step-wise Flows return the same batch
only at successful completion.

A failed Flow, timeout, cancellation, invalid Directive, or invalid candidate
state prevents dispatch of the deferred batch. Action I/O can already have
occurred and cannot be undone. Map `:collect_errors` handles errors as data;
a successful Flow retains requests from successful items only.

The third element is an optional proper list of Directives. No wrapper is
required for Flow composition. Omit the list when no Directive is needed.
Put metadata in the output state. Non-list third success elements fail at the
Action boundary. Use a Jido Action release that contains Flow effect support;
the existing published dependency requirement does not identify that release.

Use the built-in `Jido.Agent.Directive` types for supported runtime operations.
Use `SpawnChild` and `StopChild` for owned Agents. Use `SpawnProcess` only for
an untracked supervised OTP process. Declare other types through a Plugin Agent
facet. Put validation in that facet. Put optional post-commit dispatch in the
Plugin Agent Server facet. The V2
`DirectiveExec` protocol and custom `directive_handler` option are removed.

If one directive fails, the committed state remains. Later directives in that
batch do not run. Ordinary directives have no crash-replay guarantee.
Use explicit persisted intent and acknowledgement for recoverable work.
`EmitToParent` and `EmitToChild` use asynchronous casts. Their successful
Directive result means queued, not committed by the target Agent. For important
work, store a stable work ID and wait for a receiver acknowledgement after its
commit. See [Recoverable Effects](recoverable-effects.md).
For `SpawnProcess`, a raised start callback, an exit, or an unexpected start
result becomes a Directive failure after commit. The external start may already
have happened; Jido cannot undo it.

See [commit and delivery tests](../test/jido/agent/stateless_directive_test.exs)
and the [recovery examples](https://github.com/agentjido/jido/blob/release/v3/examples/04_runtime/README.md).
