# Pure or Live Execution

Your Agent runs the same routes and Actions whether you call
`Jido.Agent.cmd/3` or start a `Jido.AgentServer`. The difference is what
happens around the decision: who owns the state, whether it's saved, and
whether Directives run. This guide shows both paths and when to use each.

```elixir
agent = GettingStarted.Counter.instantiate!(id: "counter-1")
signal = GettingStarted.Counter.increment_signal!(%{amount: 2})

# Pure: returns a candidate; nothing is committed or sent
{:ok, candidate, []} = GettingStarted.Counter.cmd(agent, signal)
candidate.state.count
# => 2

# Live: the Server commits, then runs Directives
{:ok, _jido} = Jido.start()
{:ok, counter} = Jido.start_agent(agent)
{:ok, committed, []} = Jido.AgentServer.call(counter, signal)
committed.state.count
# => 2
```

`Jido.start_agent/2` accepts an instance and keeps its ID and state. You can
evaluate an Agent purely, then start a Server from the result.

## Compared

| | `cmd/3` | Agent Server |
| --- | --- | --- |
| Process | None | One per Agent |
| Success | `{:ok, candidate, directives}` | `{:ok, committed, directives}` |
| State owner | You | The Server |
| Directives | Returned as data | Run after commit |
| Persistence | No | Optional |
| Serial Turns | Only if you serialize calls | Always |
| Use for | Tests, simulations, custom runtimes | Applications and long-lived Agents |

## Pure Evaluation

`cmd/3` runs in your process. It validates the Agent and Signal, runs Plugin
`prepare/2` callbacks, runs the route, checks Directives and Plugin-owned
state, runs Plugin `reduce/2` callbacks, and validates the candidate. The
input Agent never changes.

It doesn't start a process, queue Signals, run `admit/3` or `after_commit/3`,
start Plugin runtimes, save, track revisions, run Directives, or apply replay
protection.

### Options

`context:` adds caller context. Other options go to `Jido.Exec.run/4`:

```elixir
GettingStarted.Counter.cmd(agent, signal,
  context: %{request_id: "req-1"},
  timeout: 1_000
)
```

The Action receives `request_id` next to the reserved keys `agent_id`,
`agent_signal_source`, `agent_state`, `agent_topology`, `plugin_inputs`, and
`signal`. Passing a reserved key in `context:` returns an error.

### I/O Still Runs

`cmd/3` adds no effects of its own, but your Action code runs as written. An
Action that sends an HTTP request sends it under `cmd/3` too.

Return that work as a Directive and `cmd/3` hands it back as data you can
assert on:

```elixir
reset = GettingStarted.Counter.reset_signal!()
{:ok, cleared, [%Jido.Agent.Directive.Emit{signal: signal}]} =
  GettingStarted.Counter.cmd(candidate, reset)

{cleared.state.count, signal.type}
# => {0, "counter.cleared"}
```

### Chaining

A candidate is a valid instance. Pass it to the next call:

```elixir
Enum.reduce_while(signals, {:ok, agent}, fn signal, {:ok, agent} ->
  case GettingStarted.Counter.cmd(agent, signal) do
    {:ok, next, _directives} -> {:cont, {:ok, next}}
    {:error, _reason} = error -> {:halt, error}
  end
end)
```

Jido doesn't coordinate two callers evaluating the same value. Each gets its
own candidate.

## Live Execution

The Agent Server adds:

| Capability | What you get |
| --- | --- |
| Ownership | One committed value and revision. Readers see only committed state. |
| Serial Turns | One Turn at a time, so concurrent callers can't overwrite each other. |
| Admission | Deadlines, readiness, quiescence, and cancellation. |
| Live Plugins | `admit/3`, supervised runtimes, and `after_commit/3`. |
| Persistence | Each commit saved before the reply. Hibernate and thaw. |
| Effects | Directives run after commit, in order, within `directive_timeout:`. |
| Error policy | `:log_only` by default; can stop the Server or emit an error Signal. |
| Observation | `status/2`, `history/1`, and telemetry. |

A success reply confirms the commit. Directives may still be running.

## Choosing

| You want to | Use |
| --- | --- |
| Test routes and Actions | `cmd/3` |
| Assert on returned Directives | `cmd/3` |
| Replay a list of Signals | `cmd/3` in a loop |
| Embed an Agent in your own process | `cmd/3`, and run Directives yourself |
| Accept Signals from many processes | Agent Server |
| Run Emit, AgentSend, and other Directives | Agent Server |
| Keep state across restarts | Agent Server with persistence |
| Use Plugins with runtimes | Agent Server |
| Supervise nested Agents | Agent Server |

A typical project unit-tests routes with `cmd/3` and runs Agent Servers in
integration tests and production.

## Custom Runtimes

If you build on `cmd/3` directly, you own what the Server would do:

- store the candidate and reject stale writes;
- serialize Signals per Agent;
- decide when Directives run; and
- handle failed evaluations.

## Same On Both Paths

- The first matching route runs.
- Actions return the complete next state as a plain map.
- Only the owning Plugin changes a Plugin field.
- The candidate must match the full state schema.
- A failure leaves the input or committed Agent unchanged.
- Completed Action I/O isn't undone.

## Next

- [Define an Agent](define-and-instantiate-an-agent.livemd) – definitions,
  instances, and validation in detail.
- [Routes and Handlers](build-agent-routes.livemd) – every route form.
