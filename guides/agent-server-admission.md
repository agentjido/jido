# Admission and Deadlines

An Agent Server runs one Turn at a time. Under load you need limits: how long
a Turn may wait to start, how long it may run, what happens when the queue
fills, and what the Server does after a failure. This guide covers each limit,
its default, and the exact result you get when it trips.

```elixir
{:ok, worker} =
  Jido.start_agent(MyApp.Worker,
    id: "worker-1",
    turn_timeout: 10_000,
    exec_opts: [timeout: 2_000, max_attempts: 3, backoff: :exponential],
    max_postponed_signals: 100,
    error_policy: {:max_errors, 5}
  )
```

Read [Call, Cast, and Await](send-signals-to-live-agents.livemd) first.

## The Examples

The examples use this worker. `ms` adds a delay, `fail: true` returns an
error, and `emits` returns that many `emit/2` Directives.

```elixir
defmodule MyApp.Worker do
  use Jido.Agent, name: "worker"

  state do
    schema(Zoi.object(%{done: Zoi.list(Zoi.string()) |> Zoi.default([])}))
  end

  routes do
    signal_source("/my_app/worker")

    route "job.run", as: :run do
      action %{name: name, ms: ms, fail: fail, emits: count},
        name: "run_job",
        schema:
          Zoi.object(%{
            name: Zoi.string(),
            ms: Zoi.integer() |> Zoi.default(0),
            fail: Zoi.boolean() |> Zoi.default(false),
            emits: Zoi.integer() |> Zoi.default(0)
          }),
        output_schema: Zoi.map(), context: context do
        Process.sleep(ms)

        if fail do
          {:error, :boom}
        else
          state = %{context.agent_state | done: context.agent_state.done ++ [name]}
          {:ok, state, for(i <- 1..count//1, do: emit("job.note", %{i: i}))}
        end
      end
      state from: output()
    end
  end
end

job = fn attrs ->
  signal = MyApp.Worker.run_signal!(attrs)
  signal
end

{:ok, _} = Jido.start()
```

## All Server Options

Set these when you start the Agent. They're fixed for the life of the Server.

| Option | Default | Limits |
| --- | --- | --- |
| `turn_timeout:` | `60_000` | All pre-commit work for one Turn, retries included. Non-negative integer or `:infinity`. |
| `exec_opts:` | `[]` | Per-node Action options. See below. |
| `max_postponed_signals:` | `1_000` | Turns queued behind the active one. Non-negative integer or `:infinity`. |
| `max_directives_per_turn:` | `1_000` | Directives in one Turn result. Non-negative integer or `:infinity`. |
| `directive_timeout:` | `5_000` | The whole Directive batch after commit. Finite. |
| `commit_timeout:` | `5_000` | The whole Plugin `after_commit/3` batch. Finite. |
| `readiness_timeout:` | `5_000` | Plugin runtime startup and readiness. Finite. |
| `persistence_timeout:` | `5_000` | One storage operation. Finite. |
| `error_policy:` | `:log_only` | What happens after a failed Turn. |
| `error_policy_timeout:` | `5_000` | The error policy dispatch or callback. Finite. |

An invalid value fails startup with
`{:error, %Jido.Error.ValidationError{message: "invalid <option>"}}`, for
example `"invalid directive_timeout"` for `directive_timeout: :infinity`. An
unknown key fails with `"unknown startup options"`.

Precedence, highest first: explicit start options, the instance's
`agent_server:` defaults, `config :jido, Jido.AgentServer, turn_timeout: ...`
(only `turn_timeout` is read there), then the built-in defaults.

```elixir
{:ok, _} = Jido.start_link(name: MyApp.Jido, agent_server: [turn_timeout: 100])
{:ok, from_instance} = Jido.start_agent(MyApp.Jido, MyApp.Worker, id: "inherits")
{:ok, explicit} = Jido.start_agent(MyApp.Jido, MyApp.Worker, id: "overrides", turn_timeout: 5_000)

{
  Jido.AgentServer.call(from_instance, job.(%{name: "a", ms: 300}), 2_000),
  elem(Jido.AgentServer.call(explicit, job.(%{name: "a", ms: 300}), 2_000), 0)
}
# => {{:error, :turn_timeout}, :ok}
```

## Admission

Admission is the gate before a Turn starts. Calls and submits carry an
admission deadline, `admission_timeout:`, default 5,000 ms (see
[Call, Cast, and Await](send-signals-to-live-agents.livemd)). An expired
deadline returns `{:error, :admission_timeout}`.

`max_postponed_signals:` bounds the queue. It counts Turns waiting behind the
active one, not the process mailbox. Over the limit:

- a cast is dropped and the Server logs `AgentServer cast dropped`;
- a call or submit returns `{:error, {:overloaded, %{postponed: n, limit: n}}}`.

```elixir
{:ok, small} = Jido.start_agent(MyApp.Worker, id: "small-queue", max_postponed_signals: 1)

:ok = Jido.AgentServer.cast(small, job.(%{name: "p1", ms: 200}))
:ok = Jido.AgentServer.cast(small, job.(%{name: "p2"}))
:ok = Jido.AgentServer.cast(small, job.(%{name: "p3"}))

Jido.AgentServer.call(small, job.(%{name: "p4"}), 2_000)
# => {:error, {:overloaded, %{postponed: 1, limit: 1}}}
```

`p1` runs, `p2` waits in the one queue slot, and `p3` and `p4` are rejected.

Admission also closes:

| Cause | Result for new Turns |
| --- | --- |
| Plugin runtimes not ready | `{:error, :not_ready}` until `await_ready/2` succeeds |
| `quiesce/2` | `{:error, :quiesced}` |
| A failed persistence save | The activation stops |

## Turn Deadlines

`turn_timeout:` covers everything before commit: preparation, the Action or
Flow, retries, and cleanup. When it expires, the Server stops owned work and
keeps the committed state.

```elixir
{:ok, strict} = Jido.start_agent(MyApp.Worker, id: "strict", turn_timeout: 100)
result = Jido.AgentServer.call(strict, job.(%{name: "slow", ms: 300}), 2_000)

{result, Jido.AgentServer.agent(strict).state.done,
 Jido.AgentServer.status(strict).last_outcome.status}
# => {{:error, :turn_timeout}, [], :timed_out}
```

A Turn timeout doesn't count toward `{:max_errors, n}`. It can't undo I/O
that the Action already completed.

## Per-Node Options

`exec_opts:` passes per-node options to the Action and Flow runner:

| Key | Default | Meaning |
| --- | --- | --- |
| `timeout:` | none | Deadline for one Action or Flow node attempt, in ms. |
| `max_attempts:` | `1` | Total attempts per node. |
| `backoff:` | none | Delay between attempts. |
| `base_delay_ms:` | `500` | First retry delay. |
| `max_delay_ms:` | `30_000` | Retry delay cap. |
| `max_concurrency:` | `1` | Concurrent Flow nodes. |
| `hooks:` | `[]` | Runic hooks. They run synchronously in the worker. |

A retry happens only when `Jido.Action.Error.retryable?/1` accepts the error.
`turn_timeout:` still bounds the whole Turn, retries included.

```elixir
{:ok, node_limited} = Jido.start_agent(MyApp.Worker, id: "node-limit", exec_opts: [timeout: 50])
{:error, error} = Jido.AgentServer.call(node_limited, job.(%{name: "slow", ms: 300}), 2_000)

{error.__struct__, error.timeout}
# => {Jido.Action.Error.TimeoutError, 50}
```

An unknown key fails startup with `"invalid exec_opts"`.

## Cancel a Turn

`cancel/2` stops the active Turn's pre-commit work and waits until cleanup
finishes. The caller of that Turn gets `{:error, :cancelled}`.

```elixir
{:ok, cancellable} = Jido.start_agent(MyApp.Worker, id: "cancellable")
idle = Jido.AgentServer.cancel(cancellable)

pending = Jido.AgentServer.submit(cancellable, job.(%{name: "long", ms: 1_000}))
:ok = Process.sleep(50)
turn_id = Jido.AgentServer.status(cancellable).active.turn_id

stale = Jido.AgentServer.cancel_turn(cancellable, "some-other-turn")
:ok = Jido.AgentServer.cancel_turn(cancellable, turn_id)

{idle, stale, Jido.AgentServer.await(pending, 2_000),
 Jido.AgentServer.agent(cancellable).state.done}
# => {{:error, :not_running}, {:error, :stale_turn}, {:error, :cancelled}, []}
```

| Call | Result |
| --- | --- |
| `cancel/2` on an idle Server | `{:error, :not_running}` |
| `cancel_turn/3` with another Turn's ID | `{:error, :stale_turn}` |
| Either, from work the Turn owns | `{:error, :reentrant_turn}` |
| Either, during `:saving` | `{:error, :commit_in_progress}` |
| Success | `:ok`, after cleanup |

`cancel_turn/3` protects you from cancelling a newer Turn by mistake. Read the
ID from `status/2` or from the Turn's caller. Cancellation can't stop
post-commit effects. Stop the Server to stop those.

## Quiesce and Resume

`quiesce/2` closes admission, rejects queued Turns, and waits for the active
Turn and its effects. Reads stay available. `resume/2` opens admission again.

```elixir
{:ok, draining} = Jido.start_agent(MyApp.Worker, id: "draining")

active = Jido.AgentServer.submit(draining, job.(%{name: "q1", ms: 300}))
:ok = Process.sleep(30)
queued = Jido.AgentServer.submit(draining, job.(%{name: "q2"}))
:ok = Process.sleep(30)

:ok = Jido.AgentServer.quiesce(draining)

{
  elem(Jido.AgentServer.await(active, 2_000), 0),
  Jido.AgentServer.await(queued, 2_000),
  Jido.AgentServer.call(draining, job.(%{name: "q3"})),
  Jido.AgentServer.status(draining).admission.mode,
  Jido.AgentServer.resume(draining)
}
# => {:ok, {:error, :quiesced}, {:error, :quiesced}, :quiesced, :ok}
```

| Option | Default | Meaning |
| --- | --- | --- |
| `active:` | `:finish` | `:finish` lets the active Turn complete. `:cancel` cancels pre-commit work. |
| `timeout:` | `5_000` | Finite control budget. On expiry, admission stays closed. |

Saves and effects that already started always finish. Callbacks the Server
owns can't call `quiesce/2`. `resume/2` is safe to call twice.

## Error Policy

After a failed Turn, the Server runs its error policy. The policy never
changes the failed Turn's result.

| Policy | After a failure |
| --- | --- |
| `:log_only` | Log and continue. The default. |
| `:stop_on_error` | Stop with `{:shutdown, :agent_error}`. |
| `{:max_errors, n}` | Stop with `{:shutdown, :max_agent_errors}` after `n` consecutive failures. |
| `{:emit_signal, dispatch}` | Dispatch a `jido.agent_server.error` Signal, then continue. |
| `fn error, summary -> ... end` | Return `:continue`, or `{:stop, reason}` to stop with `{:shutdown, reason}`. |

```elixir
{:ok, counted} = Jido.start_agent(MyApp.Worker, id: "counted", error_policy: {:max_errors, 2})
ref = Process.monitor(counted)

{:error, _} = Jido.AgentServer.call(counted, job.(%{name: "f1", fail: true}))
{:ok, _, []} = Jido.AgentServer.call(counted, job.(%{name: "ok"}))
reset = Jido.AgentServer.status(counted).error_count

{:error, _} = Jido.AgentServer.call(counted, job.(%{name: "f2", fail: true}))
{:error, _} = Jido.AgentServer.call(counted, job.(%{name: "f3", fail: true}))

reason =
  receive do
    {:DOWN, ^ref, :process, _, reason} -> reason
  after
    1_000 -> :still_running
  end

{reset, reason}
# => {0, {:shutdown, :max_agent_errors}}
```

A success resets the count. Cancellation and Turn timeouts don't add to it.

The error Signal and the callback's `summary` hold the Turn summary: IDs,
status, stage, commit flag, revisions, Directive count, and duration. They
never hold Agent state, Signal data, or context. The callback also receives
the error itself:

```elixir
parent = self()

policy = fn error, summary ->
  send(parent, {:policy, error.__struct__, summary.stage})
  :continue
end

{:ok, watched} = Jido.start_agent(MyApp.Worker, id: "watched", error_policy: policy)
{:error, _} = Jido.AgentServer.call(watched, job.(%{name: "f", fail: true}))

receive do
  {:policy, error_type, stage} -> {error_type, stage}
after
  1_000 -> :no_policy
end
# => {Jido.Action.Error.ExecutionFailureError, :running}
```

The dispatch or callback runs in a separate task after cleanup, bounded by
`error_policy_timeout:`. Queued Turns wait; reads don't. A policy that times
out or fails stops the Server, for example with
`{:shutdown, :error_policy_timeout}`. An incoming `jido.agent_server.error`
Signal never emits another one, so two Agents can't loop on each other's
errors.

## After the Commit

Three limits apply after commit. None of them can undo the commit or the
success reply.

`max_directives_per_turn:` is checked before commit. A larger batch fails the
Turn with `{:error, :too_many_directives}`:

```elixir
{:ok, capped} =
  Jido.start_agent(MyApp.Worker,
    id: "capped",
    max_directives_per_turn: 2,
    default_dispatch: {:pid, target: self()}
  )

{
  Jido.AgentServer.call(capped, job.(%{name: "x", emits: 3})),
  elem(Jido.AgentServer.call(capped, job.(%{name: "y", emits: 2})), 0)
}
# => {{:error, :too_many_directives}, :ok}
```

`commit_timeout:` bounds all Plugin `after_commit/3` hooks together.
`directive_timeout:` bounds the whole Directive batch. On a hook failure or
timeout, later hooks and Directives don't run. On a Directive failure or
timeout, later Directives don't run. `status/2` reports the batch result in
`last_effect_outcome`.

```elixir
for id <- ~w(inherits overrides), do: :ok = Jido.stop_agent(MyApp.Jido, id)
:ok = Jido.stop(MyApp.Jido)
:ok = Jido.stop()
```

## Next

- [Inspect Activations](inspect-and-control-activations.livemd) to read
  `status/2`, history, and snapshots.
- [Supervision and Lifecycle](agent-activation-control.md) for restarts,
  idle shutdown, and hibernation.
