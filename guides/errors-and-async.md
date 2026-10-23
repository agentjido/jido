# Errors and Async

This guide maps TypeScript error handling and async patterns to Jido. It
covers result tuples and structured errors, bang functions, why Elixir has no
async/await split, how `call/3`, `cast/3`, and `submit/3` replace Promises,
timeouts and cancellation, backpressure, failures after commit, and what
"let it crash" means for a live Agent.

> #### Learn Elixir first {: .tip}
>
> This guide assumes you can read basic Elixir. The official guides cover it:
> [Introduction](https://hexdocs.pm/elixir/introduction.html),
> [Pattern matching](https://hexdocs.pm/elixir/pattern-matching.html),
> [Processes](https://hexdocs.pm/elixir/processes.html), and
> [Keyword lists and maps](https://hexdocs.pm/elixir/keywords-and-maps.html).

Jido returns failures as values you match. Only an expired caller timeout and
a Server crash exit the caller instead:

```elixir
case Jido.AgentServer.call(counter, Guides.Counter.increment_signal!(%{amount: 20})) do
  {:ok, agent, _directives} -> {:committed, agent.state.count}
  {:error, %{details: %{code: :over_limit}}} -> :over_limit
  {:error, :turn_timeout} -> :too_slow
  {:error, reason} -> {:failed, reason}
end
# => :over_limit
```

## The Example Agent

The examples use one counter. `increment` adds `amount` after sleeping `ms`
milliseconds and refuses to go past 10. `notify` adds one and sends a Signal to
the process in `to`.

```elixir
defmodule Guides.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/guides/errors-and-async")

    route "counter.increment", as: :increment do
      action %{amount: amount, ms: ms},
        name: "increment",
        schema: Zoi.object(%{amount: Zoi.integer(), ms: Zoi.integer() |> Zoi.default(0)}),
        output_schema: Zoi.map(), context: context do
        Process.sleep(ms)
        state = context.agent_state

        if state.count + amount > 10 do
          {:error,
           Jido.Action.Error.execution_error("limit reached", %{code: :over_limit, limit: 10})}
        else
          {:ok, %{state | count: state.count + amount}}
        end
      end
      state from: output()
    end

    route "counter.notify", as: :notify do
      action %{to: to}, name: "notify", schema: Zoi.object(%{to: Zoi.any()}), output_schema: Zoi.map(), context: context do
        state = context.agent_state
        signal = Jido.Signal.new!("counter.changed", %{}, source: "/guides/errors-and-async")
        {:ok, %{state | count: state.count + 1}, [emit(signal, {:pid, target: to})]}
      end
      state from: output()
    end
  end
end

{:ok, _} = Jido.start()
{:ok, counter} = Jido.start_agent(Guides.Counter, id: "counter-1")
```

## Results, Not Throws

In TypeScript you usually `await` inside `try`, race a timer, and sort out the
`catch`:

```typescript
async function increment(amount: number): Promise<number> {
  const timeout = new Promise<never>((_, reject) =>
    setTimeout(() => reject(new Error("timeout")), 5000),
  );
  try {
    const res = await Promise.race([fetch(`/counter?amount=${amount}`), timeout]);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return (await res.json()).count;
  } catch (err) {
    // err is `unknown`: a network error, the timeout, or your own throw
    return -1;
  }
}
```

In Jido, `call/3` returns `{:ok, agent, directives}` or `{:error, reason}`.
The deadlines are options, and you `case` on the result:

```elixir
signal = Guides.Counter.increment_signal!(%{amount: 3})

case Jido.AgentServer.call(counter, signal, timeout: 5_000, admission_timeout: 1_000) do
  {:ok, agent, []} -> {:ok, agent.state.count}
  {:error, :admission_timeout} -> {:error, :busy}
  {:error, reason} -> {:error, reason}
end
# => {:ok, 3}
```

Where the analogy breaks:

- The type of `reason` isn't one union. Domain and execution failures are
  exception structs. Runtime limits are atoms or tuples: `:admission_timeout`,
  `:turn_timeout`, `:cancelled`, `{:overloaded, %{postponed: n, limit: n}}`.
- The caller `timeout:` is not a result. When it expires, the caller
  exits. See [Cancel and Timeouts](#cancel-and-timeouts).
- A failed Turn leaves state unchanged. A rejected Promise tells you nothing
  about what the server already did.

The `{:error, ...}` from the opening example is a struct:

```elixir
{:error, error} = Jido.AgentServer.call(counter, Guides.Counter.increment_signal!(%{amount: 20}))
error
# => %Jido.Action.Error.ExecutionFailureError{
#      message: "limit reached",
#      details: %{code: :over_limit, limit: 10},
#      class: :execution, ...}

{Exception.message(error), Jido.AgentServer.agent(counter).state.count}
# => {"limit reached", 3}
```

Jido errors are Elixir exceptions, so `Exception.message/1` works on all of
them. Match on `class` or on `details`, not on the message text. These are the
shapes you see from Actions:

| Cause | Struct | `message` | `class` |
| --- | --- | --- | --- |
| Your `execution_error/2` | `Jido.Action.Error.ExecutionFailureError` | Your text | `:execution` |
| Input fails the Action schema (`amount: "x"`) | `Jido.Action.Error.InvalidInputError` | `"invalid type: expected integer, at amount"` | `:invalid` |
| The Action raises `"boom"` | `Jido.Action.Error.ExecutionFailureError` | `"boom"`, with `details.exception: RuntimeError` | `:execution` |
| No route matches | `Jido.Agent.Error`, `code: :unmatched_input` | `"No route accepts this Signal type"` | none |

`Jido.Error.code/1` reads only Jido's own stable codes. For your code
`:over_limit` it returns `nil`, so match `error.details.code` directly.

> #### Not every error is a struct {: .warning}
>
> Some public boundaries return unstructured reasons. A Plugin `prepare/2` or
> `admit/3` rejection comes back as the Plugin returned it. An invalid custom
> Directive returns a raw `[%Zoi.Error{}]` list. Keep a final
> `{:error, reason}` clause in every `case`.

## Bang Functions

`as: :increment` on a route generates two Signal constructors. The name tells
you how it fails:

| Function | Success | Failure |
| --- | --- | --- |
| `increment_signal/2` | `{:ok, signal}` | `{:error, reason}` |
| `increment_signal!/2` | The Signal | Raises |

```elixir
Guides.Counter.increment_signal(amount: 2)
# => {:error, %Jido.Agent.Error{message: "Expected a plain Map", code: :invalid_map, ...}}

Guides.Counter.increment_signal!(amount: 2)
# ** (Jido.Agent.Error) Expected a plain Map
```

The bang form raises the exception struct when the reason is one. Otherwise
it raises `ArgumentError`:

```elixir
Guides.Counter.increment_signal!(%{amount: 1}, id: 123)
# ** (ArgumentError) invalid input Signal: "parse error: invalid type: expected string, at id"
```

Neither constructor checks the data against the Action schema or runs
anything. `increment_signal!(%{amount: "x"})` returns a Signal; the Turn
fails later with `InvalidInputError`.

Use the bang form when bad input is a bug in your own code, such as a literal
in a test. Use the plain form when the input comes from outside. The same
rule holds across Elixir: `File.read/1` and `File.read!/1`,
`Jido.Signal.new/3` and `Jido.Signal.new!/3`.

## No Async Coloring

In TypeScript, a function that awaits must be `async`, and so must every
caller that wants its value. Elixir has no such split. `call/3` is an ordinary
function. It blocks the process that calls it, and only that process. Every
other process keeps running.

To do two things at once, run them in two processes:

```elixir
{:ok, a} = Jido.start_agent(Guides.Counter, id: "a")
{:ok, b} = Jido.start_agent(Guides.Counter, id: "b")
slow = Guides.Counter.increment_signal!(%{amount: 1, ms: 300})

[a, b]
|> Enum.map(fn server -> Task.async(fn -> Jido.AgentServer.call(server, slow) end) end)
|> Task.await_many()
|> Enum.map(&elem(&1, 0))
# => [:ok, :ok]
```

Both Turns finish in about 400 ms, not 600 ms. The Agent Server also stays
responsive during its own Turn. `Jido.AgentServer.agent/2` and `status/2`
return at once, with `phase: :running`, while a 300 ms Turn runs.

Where the analogy breaks: Node runs your code on one event loop, so an
`await` gives the thread back. A BEAM process that waits in `call/3` does
nothing else until the reply or the timeout. Concurrency comes from more
processes, not from not awaiting. See
[Node.js and the BEAM](nodejs-and-the-beam.md).

## Call, Cast, Submit

| You write in TypeScript | Jido | Returns |
| --- | --- | --- |
| `await fetch(...)` | `call/3` | `{:ok, agent, directives}` or `{:error, reason}` after commit |
| `void fetch(...)` | `cast/3` | `:ok` once sent |
| `const p = fetch(...)` … `await p` | `submit/3` … `await/2` | A handle, then the same result as `call/3` |

A fire-and-forget Promise loses its error unless something catches it:

```typescript
function bump(amount: number): void {
  void fetch(`/counter?amount=${amount}`, { method: "POST" });
  // A rejection here goes to an unhandled-rejection handler, or nowhere.
}
```

`cast/3` returns `:ok` even when the Turn fails. The Server logs
`AgentServer cast turn failed` with the Turn ID and records the outcome.
Read it with `status/2`:

```elixir
:ok = Jido.AgentServer.cast(counter, Guides.Counter.increment_signal!(%{amount: 50}))
Process.sleep(100)

Jido.AgentServer.status(counter).last_outcome
# => %{status: :failed, stage: :running, committed?: false,
#      signal_id: "01a1...", turn_id: "01a1...",
#      state_version_before: 1, state_version_after: 1,
#      directive_count: 0, duration_ms: 4}
```

Where the analogy breaks: `last_outcome` holds only the most recent Turn, and
it never includes the raw error. Match `signal_id` against your Signal's `id`
to know the outcome is yours. Use `call/3` or `submit/3` when you need the
error.

`submit/3` is the closest thing to holding a Promise. `await/2` collects the
result once, from the submitting process. An `await/2` timeout returns
`{:error, :timeout}` and keeps the reply, so you can wait again:

```elixir
pending = Jido.AgentServer.submit(counter, Guides.Counter.increment_signal!(%{amount: 1, ms: 200}))

{Jido.AgentServer.await(pending, 10), elem(Jido.AgentServer.await(pending, 2_000), 0)}
# => {{:error, :timeout}, :ok}
```

Unlike a Promise, the handle can't move to another process. `await/2` from a
different process returns a `ValidationError` with
`"await must run in the process that submitted the turn"`.
[Call, Cast, and Await](send-signals-to-live-agents.livemd) covers each
option.

## Cancel and Timeouts

`Promise.race` with a timer stops your wait, but the request keeps running.
`AbortController` stops the request. Jido has the same split:

| TypeScript | Jido | Default | Stops the work |
| --- | --- | --- | --- |
| `Promise.race` with `setTimeout` | `timeout:` on `call/3` | 5,000 ms | No |
| A queue entry that expires | `admission_timeout:` on `call/3` and `submit/3` | 5,000 ms | Yes, it never starts |
| `AbortSignal.timeout(ms)` on the server | `turn_timeout:` at start | 60,000 ms | Yes, before commit |
| `controller.abort()` | `cancel/2`, `cancel_turn/3` | — | Yes, before commit |
| Dropping a Promise you don't need | `abandon/1` | — | No |

A caller timeout exits the caller. The Turn still commits:

```elixir
{:ok, worker} = Jido.start_agent(Guides.Counter, id: "worker")
slow = Guides.Counter.increment_signal!(%{amount: 1, ms: 300})

try do
  Jido.AgentServer.call(worker, slow, timeout: 50)
catch
  :exit, {reason, {:gen_statem, :call, _args}} -> {:exit, reason}
end
# => {:exit, :timeout}

Process.sleep(400)
Jido.AgentServer.agent(worker).state.count
# => 1
```

The limits that stop work return errors instead:

```elixir
:ok = Jido.AgentServer.cast(worker, slow)
Jido.AgentServer.call(worker, slow, admission_timeout: 50, timeout: 2_000)
# => {:error, :admission_timeout}

{:ok, strict} = Jido.start_agent(Guides.Counter, id: "strict", turn_timeout: 100)
{Jido.AgentServer.call(strict, slow, 2_000), Jido.AgentServer.status(strict).last_outcome.status}
# => {{:error, :turn_timeout}, :timed_out}

pending = Jido.AgentServer.submit(worker, slow)
:ok = Jido.AgentServer.abandon(pending)
```

`abandon/1` returns `:ok` and discards the reply. The Turn still runs.

Where the analogy breaks: an `AbortSignal` works only if the code you call
checks it. Jido stops the work the Turn owns, with no checks in your Action.
It can't undo I/O the Action already did, and nothing cancels work after
commit. `cancel/2` during a save returns `{:error, :commit_in_progress}`.
[Admission and Deadlines](agent-server-admission.md) covers `cancel_turn/3`,
`quiesce/2`, and per-node `exec_opts:` timeouts.

## Backpressure

In TypeScript you add a hand-rolled concurrency limiter or a queue in front
of shared state. An Agent Server already is one: it runs one Turn at a time,
in arrival order. Three 100 ms submits to one Agent take about 300 ms and
return counts 1, 2, 3 in order.

The queue behind the active Turn has a bound, `max_postponed_signals:`
(default 1,000):

```elixir
{:ok, small} = Jido.start_agent(Guides.Counter, id: "small", max_postponed_signals: 1)

:ok = Jido.AgentServer.cast(small, Guides.Counter.increment_signal!(%{amount: 1, ms: 200}))
:ok = Jido.AgentServer.cast(small, Guides.Counter.increment_signal!(%{amount: 1}))

Jido.AgentServer.call(small, Guides.Counter.increment_signal!(%{amount: 1}), 2_000)
# => {:error, {:overloaded, %{postponed: 1, limit: 1}}}
```

Over the limit, a call or submit gets `{:overloaded, ...}`. A cast is dropped,
and only the Server log shows it (`AgentServer cast dropped`).
`admission_timeout:` sheds work that waited too long.

Where the analogy breaks: the limit is per Agent, and the concurrency is
always 1. There are no priorities. For more throughput, split the state across
more Agents.

## Failure After Commit

In TypeScript, a handler that writes a row and then sends mail can fail
between the two:

```typescript
app.post("/orders", async (req, res) => {
  await db.insert(order);  // committed
  await mailer.send(order); // throws
  res.json(order);          // never runs; the client sees a 500
});
```

Jido commits, replies, then runs Directives. A failed Directive doesn't roll
back the state, and the caller already has `:ok`:

```elixir
gone = spawn(fn -> :ok end)
{:ok, agent, [_emit]} = Jido.AgentServer.call(worker, Guides.Counter.notify_signal!(%{to: gone}))
Process.sleep(100)

{agent.state.count, Jido.AgentServer.status(worker).last_effect_outcome}
# => {4, %{status: :failed, stage: :directive, total: 1, completed: 0,
#          committed_version: 4, turn_id: "01a1..."}}
```

`last_outcome` reads `status: :succeeded, stage: :commit` for the same Turn.
`directive_timeout:` (default 5,000 ms) bounds the whole Directive batch, and
`commit_timeout:` (default 5,000 ms) bounds the Plugin `after_commit/3` hooks.
A failure or timeout stops the rest of the batch. The commit stands.

Where the analogy breaks: the TypeScript client sees the failure, and the
Jido caller doesn't. Nothing retries the Directive. To make an effect
survive, save the intent in state in the same Turn, then deliver it from an
outbox. See [Recovery Limits](recovery-and-effect-limits.md).

## Let It Crash

"Let it crash" means a supervisor restarts a failed process from a known
state, instead of each function guarding against every fault. In Jido it
applies at two levels.

An exception in your Action doesn't crash the Server. The Turn fails with
`ExecutionFailureError`, state stays at the last commit, and the error policy
runs (default `:log_only`). You don't need `try` in an Action.

When the Server process itself dies mid-Turn, the caller exits with the
crash reason, and the in-flight Turn is lost:

```elixir
{:ok, k} = Jido.start_agent(Guides.Counter, id: "k1")
{:ok, _, []} = Jido.AgentServer.call(k, Guides.Counter.increment_signal!(%{amount: 4}))
spawn(fn -> Process.sleep(50) && Process.exit(k, :kill) end)

try do
  Jido.AgentServer.call(k, Guides.Counter.increment_signal!(%{amount: 1, ms: 300}), 2_000)
catch
  :exit, {reason, {:gen_statem, :call, _args}} -> {:exit, reason}
end
# => {:exit, :killed}

Process.sleep(300)
restarted = Jido.whereis_agent("k1")
{restarted != k, Jido.AgentServer.agent(restarted).state.count, Jido.AgentServer.status(restarted).state_version}
# => {true, 4, 1}
```

A pending `submit/3` handle returns
`{:error, %Jido.Error.ExecutionError{message: "Agent server stopped before the turn replied", details: %{reason: :killed}}}`
instead of an exit.

What the restart keeps:

| Failure | Without persistence | With persistence |
| --- | --- | --- |
| Server process crash | Last committed state and revision | Last committed state and revision |
| Whole activation crash | Initial state, revision 0, with no error | Last stored revision |
| BEAM restart | Nothing | Last stored revision, after you start the Agent with `persistence_mode: :restore` |

Persistence is off unless you pass `persistence: :inherit` or an adapter for
that Agent. The restart never replays the lost Turn, its Signals, or its
Directives. Where the analogy breaks with a crashed Node process: a restarted
Agent comes back with its committed state, not empty, but only for as long as
its activation lives. [Supervision and Lifecycle](agent-activation-control.md)
covers restart limits.

```elixir
:ok = Jido.stop()
```

## Next

- [Effects as Data](effects-as-data.md) for why Actions return Directives
  instead of running side effects.
- [OTP Concepts](otp-concepts-for-jido.md) for processes, supervisors, and
  messages in Jido terms.
- [Life of a Signal](signal-to-effects.md) for each stage and its failure
  rule.
