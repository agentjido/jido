# Life of a Signal

When a Turn fails, you need to know what changed and what didn't. Every
Signal that reaches an Agent runs through the same stages in the same order,
and each stage has a fixed failure rule. This guide walks one Signal from
admission to its last effect.

```text
Signal
  -> admission         accept the Turn, or reject it
  -> preparation       Plugins prepare input; select one route
  -> execution         one Action or Flow returns next state and Directives
  -> composition       check Directives; Plugins reduce their state
  -> validation        validate the complete candidate Agent
  -> save              store the candidate (when persistence is on)
  -> commit, reply     publish the new revision; reply to the caller
  -> commit hooks      Plugin after_commit/3 callbacks
  -> effects           Directives run in order
```

Every stage before commit can fail with no change to the Agent. Every stage
after commit runs on committed state and can't undo it.

`Jido.Agent.cmd/3` runs preparation through validation. The Agent Server runs
all of it. The examples use `GettingStarted.Counter` from
[Getting Started](getting-started.livemd).

## The Signal

A Signal is a `Jido.Signal` struct in CloudEvents format. Jido reads three
fields:

| Field | Use |
| --- | --- |
| `type` | Selects the route. Must be exact, such as `"counter.increment"`. |
| `data` | The Action or Flow input. A map, keyword list, or `nil`. |
| `id` | Identifies the Signal in Turn summaries, logs, and causation. |

Route constructors such as `increment_signal!/2` set `source` from the Agent's
`signal_source`. `Jido.Signal.new/3` builds one by hand. The Signal doesn't
change during the Turn.

## Admission

A live Turn starts when `call/3`, `cast/3`, or `submit/3` delivers a Signal.
The Server rejects it before it starts when:

- the admission deadline passes while it waits (`admission_timeout:`,
  default 5,000 ms, calls and submits only);
- Plugin runtimes aren't ready (`{:error, :not_ready}`); or
- admission is closed by `quiesce/2` or a failed save.

`context:` on a call adds caller data, such as a request ID. The Action
receives it in its context map. It isn't stored in state or in the Signal.

## Preparation

1. **`prepare/2`.** Each Plugin that defines it runs in declaration order and
   returns portable input at `context.plugin_inputs[Plugin].prepared`.
2. **`admit/3`.** On a live Server only, each Plugin that defines it can
   reject the Turn or return runtime input at
   `context.plugin_inputs[Plugin].runtime`.
3. **Route selection.** Jido takes the first route, in declaration order,
   whose path matches the Signal type. Paths are exact or use `*` wildcards,
   such as `"counter.*"`. No match fails the Turn with
   `"No route accepts this Signal type"`.

| Handler | Runs | Changes state |
| --- | --- | --- |
| Action | A `Jido.Action` module or an inline `action` block | Yes |
| Flow | A `Jido.Flow` module | Yes |
| Transform | A function from Signal to one output Signal | No |
| Forward | Sends the input Signal to one named child or the parent. | No |

For Action and Flow routes, the input is the route `defaults:` merged with the
Signal data. Signal data wins on equal keys. A transform returns one `Emit`.
A forward returns one `AgentSend` or `ParentSend`. Neither accepts `defaults:`.

## Execution

Jido runs the handler through `Jido.Exec.run/4`. The context holds your
caller context plus six reserved keys:

| Key | Value |
| --- | --- |
| `agent_id` | The instance ID. |
| `agent_signal_source` | The Agent's declared Signal source. |
| `agent_state` | The committed state at the start of the Turn. |
| `agent_topology` | Declared child Agents and connections. |
| `plugin_inputs` | Prepared and runtime input per Plugin. |
| `signal` | The source Signal. |

The handler returns one of:

```elixir
{:ok, next_state}
{:ok, next_state, directives}
{:error, reason}
```

`next_state` is the complete state as a plain map:
`%{state | count: state.count + amount}`. `directives` must be a proper list.

Actions can do I/O. That I/O happens before commit. If the Turn fails later,
the committed state is untouched but the HTTP request was still sent. Make
those calls idempotent, or return them as Directives so they run after
commit.

On a live Server, `turn_timeout:` (default 60,000 ms) limits all pre-commit
work, retries included. `exec_opts:` sets per-node `timeout:`,
`max_attempts:`, and `backoff:`.

## Composition

Jido checks the result as one batch:

1. Each `emit/2` request becomes an `Emit` Directive with a full Signal
   envelope, sourced from the Agent's `signal_source`.
2. The handler must not change a Plugin-owned state field.
3. Each Directive must be built in, define `validate/1`, or be owned by a
   Plugin.
4. Each Plugin with `reduce/2` updates its own field.
5. Topology, route, and Plugin Directives edit the candidate's definition.

`max_directives_per_turn:` caps the batch at 1,000 by default.

## Validation

Jido validates the candidate against the full state schema, including Plugin
fields. A mismatch fails the Turn:

```text
{:error, %Jido.Agent.Error{message: "State does not match its schema"}}
```

`cmd/3` stops here and returns `{:ok, candidate, directives}`.

## Save

With persistence on, the Server enters `:saving` and writes the candidate
with the next revision before publishing it. Reads still work. New Turns
wait. A caller timeout doesn't cancel the write.

A failed or uncertain write ends the activation: no success reply, no hooks,
no Directives. Without persistence, committed state lasts as long as the
activation.

## Commit And Reply

The Server publishes the candidate, adds one to the revision, and replies:

```elixir
{:ok, committed_agent, directives} = Jido.AgentServer.call(counter, signal)
```

The reply confirms the commit, not the Directives. Read the last Turn's
outcome with `status/2`:

```elixir
Jido.AgentServer.status(counter).last_outcome
# => %{status: :succeeded, stage: :commit, committed?: true,
#      state_version_before: 0, state_version_after: 1,
#      directive_count: 0, ...}
```

Summaries hold IDs, status, stage, revisions, Directive count, and duration.
They never include Signal data, state, or raw errors.

## Commit Hooks

Each Plugin's `after_commit/3` runs in declaration order, on every commit.
`commit_timeout:` (default 5,000 ms) limits the whole batch. A failing hook
stops later hooks and all Directives. The commit stands.

## Effects

Directives run in order, in linked tasks, before the next Turn starts.
`directive_timeout:` (default 5,000 ms) limits the whole batch. An error or
timeout stops the batch. The commit stands. `status/2` reports progress in
`effects` and the result in `last_effect_outcome`.

### Emit Destinations

An `Emit` Directive goes to the first of:

1. the `dispatch` set on the Directive with `emit(signal, dispatch)`;
2. accepted topology connections;
3. the owning topology, when the Agent is a declared child;
4. the Server's `default_dispatch:` option; or
5. the same Agent Server, as a cast.

Plugins with `prepare_outbound/4` can prepare the outbound Signal. It keeps
the source Signal's trace and causation.

> #### Emits default to the same Agent {: .warning}
>
> With no other destination, an emitted Signal starts a new Turn on the same
> Agent. A route that matches its own emitted type loops. A type with no route
> fails the new Turn. Set `default_dispatch:`, or emit types a route handles on
> purpose.

### Built-In Directives

| Directive | Effect |
| --- | --- |
| `Jido.Agent.Directive.Emit` | Dispatches one Signal. |
| `Jido.Agent.Directive.Reply` | Sends one correlated response to the current requester. |
| `Jido.AgentServer.Directive.AgentSend` | Sends a Signal to another Agent. |
| `Jido.AgentServer.Directive.ParentSend` | Sends a Signal to the parent Agent. |
| `Jido.AgentServer.Directive.AgentStart` | Starts an Agent. |
| `Jido.AgentServer.Directive.AgentStop` | Stops an Agent. |
| `Jido.AgentServer.Directive.ProcessStart` | Starts a process under the instance. It can outlive the Server. |
| `Jido.AgentServer.Directive.ErrorReport` | Applies the error policy after commit. |
| `Jido.AgentServer.Directive.ServerStop` | Stops the Server. Must be last. |

## Failure Rules

A failure at any pre-commit stage:

- returns `{:error, reason}` to the caller;
- leaves the committed Agent and revision unchanged;
- runs no hooks and no Directives; and
- doesn't undo I/O an Action already did.

The Server then runs its error policy. The default, `:log_only`, logs and
continues. Other policies stop the Server after one error or a count of
consecutive errors, or emit an error Signal.

Cancels and Turn timeouts stop owned work before commit and keep the
committed state. Once the Server reaches `:saving`, cancellation returns
`{:error, :commit_in_progress}`.

## Pure vs Live Stages

| Stage | `cmd/3` | Agent Server |
| --- | --- | --- |
| Admission | No | Yes |
| `prepare/2` | Yes | Yes |
| `admit/3` | No | Yes |
| Route and execution | Yes | Yes |
| Composition and validation | Yes | Yes |
| Save | No | When persistence is on |
| Commit and reply | Returns a candidate | Yes |
| `after_commit/3` | No | Yes |
| Directives | Returns them | Runs them |
| Error policy | No | Yes |

## Next

- [Pure or Live Execution](pure-or-live-execution.md) – choose between `cmd/3`
  and an Agent Server.
- [State and Directives](agent-results-and-directives.md) – result shapes and
  every Directive in detail.
