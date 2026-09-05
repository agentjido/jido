> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Errors

[Design overview](README.md) | Previous: [Observability](observability.md) | Next: [Runtime extension boundaries](runtime-extension-boundaries.md)

- Status: Proposal for v3 spike review
- Depends on: Splode and all public Jido API boundaries.
- Defines: the public error classes, normalization rules, and safe error
  projection.

## Boundary

Jido uses Splode and defined error modules. It does not add a generic Zoi
error struct.

Normal shaped success data uses Zoi structs. Errors are the explicit
exception. Splode owns their exception structs, class hierarchy, composition,
and conversion behavior.

Jido command, construction, and lifecycle result positions return errors in
tagged tuples:

```elixir
{:error, %Jido.Error.ValidationError{}}
{:error, %Jido.Error.PersistenceError{}}
```

These result positions do not return an arbitrary error term. Jido normalizes
errors from application callbacks, OTP tasks, providers, and dependencies
before the error crosses the instance or Agent result boundary.

Bang functions raise the same defined errors. They do not use a second error
model.

## Defined errors

The proposed v3 core error set is:

| Error | Purpose |
| --- | --- |
| `Jido.Error.ValidationError` | Invalid Agent, Plugin, Signal, Directive, option, schema result, or callback return. |
| `Jido.Error.RoutingError` | No Agent route, an invalid route, or an invalid delivery target. |
| `Jido.Error.ExecutionError` | Action, Flow, Plugin callback, or Turn evaluation failure. |
| `Jido.Error.TimeoutError` | Admission, Turn, readiness, or Directive timeout. |
| `Jido.Error.PersistenceError` | Load, compare-and-swap, conflict, timeout, indeterminate write, tombstone, definition revision mismatch, or restore failure. |
| `Jido.Error.RuntimeError` | Agent Server lifecycle, Plugin runtime, Directive dispatch, overload, cancellation, or reentry failure. |
| `Jido.Error.InternalError` | Broken Jido invariant or unexpected framework failure. |

Each error module has a fixed Splode class and a closed documented field set.
Each error also has a stable `code` field for program decisions. The message
is for people and is not a stable program key.

`Jido.Error.t()` means a defined error accepted by the active Jido Splode. A
direct Agent call uses the core composition. A Jido instance can compose
defined package errors. The type does not include arbitrary exceptions or
returned terms. Command, construction, and lifecycle specifications use this
type instead of `term()`.

Example:

```elixir
%Jido.Error.PersistenceError{
  code: :conflict,
  message: "Agent record changed before commit",
  operation: :commit,
  agent_ref: agent_ref,
  retryable?: true,
  details: %{}
}
```

Error fields can refer to public identity values such as `Agent.Ref`, Plugin
ID, Turn ID, Signal ID, and stable Directive ID. They must not contain Agent
state, Plugin state, Signal data, checkpoints, persistence records, or
Directive payloads.

The stable timeout codes are `:admission_timeout`, `:turn_timeout`,
`:readiness_timeout`, and `:directive_timeout`. The stable cancellation control
codes are `:turn_cancelled`, `:no_active_turn`, `:turn_mismatch`, and
`:too_late`. They use `Jido.Error.RuntimeError` because they report the current
Server control stage.

A persistence callback timeout has an unknown write result. Jido normalizes it
to `Jido.Error.PersistenceError` with code `:indeterminate`, not to a general
timeout error. The current Agent Server then stops with the internal shutdown
reason `:lost_write_authority`. This shutdown reason is not a public command
result code.

## Splode classes

The initial class order is:

```elixir
[
  invalid: Jido.Error.Invalid,
  routing: Jido.Error.Routing,
  execution: Jido.Error.Execution,
  timeout: Jido.Error.Timeout,
  persistence: Jido.Error.Persistence,
  runtime: Jido.Error.Runtime,
  internal: Jido.Error.Internal
]
```

Packages in the Jido ecosystem can define package errors under these classes
or compose their own Splode with Jido. Core does not copy a dependency error
when that error already follows the composed Splode contract.

Package-specific concepts stay with their package. For example, compensation
errors belong to `jido_action` unless Jido core adds a compensation state
machine of its own.

## Protocol control values

Some public functions implement established data or OTP protocols. Their
control values are not Jido error result positions:

| Boundary | Control result |
| --- | --- |
| `Agent.fetch_state/2` and `Agent.fetch_plugin_state/3` | `:error`, as for `Map.fetch/2`. |
| Asynchronous `receive_response/2` | `:timeout` or the standard OTP request-down envelope. |
| Best-effort `cast/3` | `:ok` confirms only that Jido sent the message. |
| `whereis_local/2` | A local PID or nil. |
| Instance `child_spec/1` and `start_link/1` | Standard OTP child and start results. |

These exceptions are complete. A new raw control value requires an explicit
entry in this table. All command and lifecycle failures still use a defined
Splode error.

## Callback normalization

Application callbacks should return a defined Jido or composed Splode error:

```elixir
{:error, error}
```

Jido still protects the framework boundary:

- A defined composed error passes through.
- A fixed provider control atom is converted to its defined Jido error.
- Another returned value becomes an error for that boundary.
- A raised exception becomes the matching defined Jido error and keeps the
  original exception as an internal cause when safe.
- A throw or exit from application work becomes an execution or runtime
  error.
- A broken internal invariant exits the Agent Server. OTP then restores it.

Public callback specifications use `Jido.Error.t()` for normalized error
results. Provider callbacks can also return their fixed control atoms because
those atoms are part of the provider protocol.

## Provider control values

Persistence callbacks can return these fixed values:

```elixir
:not_found | :conflict | :indeterminate
```

They are control tags, not shaped error data. The Jido instance converts them
to `Jido.Error.PersistenceError` before returning an error through its public
API.

If Jido reaches `persistence_timeout` before a write callback returns, it uses
the same `:indeterminate` PersistenceError meaning. It cannot assume that the
provider did not write the Record.

The same rule applies to fixed OTP reply tags such as `:timeout`. Public Jido
APIs normalize the terminal failure to a defined error.

## Safe projection

`Jido.Error.to_map/1` returns a bounded public projection for telemetry, logs,
and transport:

```elixir
%{
  class: :persistence,
  type: Jido.Error.PersistenceError,
  code: :conflict,
  message: "Agent record changed before commit",
  retryable?: true,
  operation: :commit
}
```

The projection excludes stacktraces, raw causes, state, payloads, and complete
runtime values. It is not a persistence format for the original exception.

Logger and OTP crash reports can contain stacktraces under their normal
policies. Core telemetry does not.

## Required tests

- Each command, construction, and lifecycle failure returns a defined Jido or
  composed Splode error.
- Each raw protocol control value is one of the explicit exceptions in this
  document.
- Each defined error has a stable class and code.
- Fixed persistence control values normalize to `PersistenceError`.
- A persistence write timeout normalizes to an indeterminate
  `PersistenceError` and removes the current Server's write authority.
- Turn and Directive timeouts use their distinct stable codes.
- Cancellation errors distinguish no active Turn, a mismatched Turn ID, and a
  request that reached the Server after the commit boundary.
- Invalid callback returns normalize to the correct boundary error.
- Bang and tagged-result APIs use the same error definitions.
- `to_map/1` is bounded and contains no state or payload.
- A broken internal invariant still exits the Agent Server.
