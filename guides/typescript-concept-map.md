# TypeScript Concept Map

This guide maps patterns you already write in TypeScript to their closest Jido
equivalents. Each row names the Jido API, says where the analogy breaks, and
links to the guide that covers it.

> #### Learn Elixir first {: .tip}
>
> This guide assumes you can read basic Elixir. The official guides cover it:
> [Introduction](https://hexdocs.pm/elixir/introduction.html),
> [Pattern matching](https://hexdocs.pm/elixir/pattern-matching.html),
> [Processes](https://hexdocs.pm/elixir/processes.html), and
> [Keyword lists and maps](https://hexdocs.pm/elixir/keywords-and-maps.html).

A reducer you write by hand:

```typescript
type State = { count: number };
type Event = { type: "counter.increment"; amount: number };

function reducer(state: State, event: Event): State {
  switch (event.type) {
    case "counter.increment":
      return { ...state, count: state.count + event.amount };
  }
}
```

The same logic as a Jido Action and route:

```elixir
defmodule MyApp.Increment do
  use Jido.Action,
    name: "increment",
    description: "Adds an amount to the count",
    schema: Zoi.object(%{amount: Zoi.integer()}),
    output_schema: Zoi.map()

  @impl true
  def run(%{amount: amount}, %{agent_state: state}),
    do: {:ok, %{state | count: state.count + amount}}
end

defmodule MyApp.Counter do
  use Jido.Agent, name: "counter", description: "Counts increments"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/counter")
    route "counter.increment", MyApp.Increment, as: :increment do
      state from: output()
    end
  end
end

agent = MyApp.Counter.instantiate!(id: "counter-1")
signal = MyApp.Counter.increment_signal!(%{amount: 2})
{:ok, next, []} = MyApp.Counter.cmd(agent, signal)
next.state.count
# => 2
```

## State and Updates

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| A reducer `(state, event) => state` | An Action's `run/2` returns `{:ok, next_state}` | Jido validates the result against the full state schema before commit. A mismatch fails the Turn. An Action can also do I/O. | [State and Directives](agent-results-and-directives.md) |
| Object spread `{...state, count: 1}` | `%{state \| count: 1}` | The update syntax changes existing keys only. A missing key raises `KeyError`. A new key fails the schema with `unrecognized key`. | [Mutations and Diffs](agent-mutations-and-diffs.livemd) |
| A partial patch that the store merges | No equivalent. Return the complete state. | Jido doesn't merge. Returning `%{}` fails with code `:incomplete_state`, even when the schema has defaults. | [State and Directives](agent-results-and-directives.md) |
| A store object | A `%Jido.Agent{}` instance from `instantiate!/1` | It's an immutable value. `cmd/3` returns a new candidate and leaves the input unchanged. | [Define an Agent](define-and-instantiate-an-agent.livemd) |
| A live store with subscribers | A `Jido.AgentServer` process; read with `Jido.AgentServer.agent/2` | One process per Agent and one Turn at a time. Readers see only committed state. No change subscriptions. | [Start and Address Agents](start-and-address-live-agents.livemd) |

## Effects

Directives are effect requests returned as data. The Agent Server runs them
after it commits the state.

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| Effect middleware that runs after the reducer | Directives: `{:ok, state, directives}` | Directives run only after commit, in order, within `directive_timeout:` (default 5,000 ms). A failed Turn runs none. A failed Directive doesn't roll back the commit. | [State and Directives](agent-results-and-directives.md) |
| `emitter.emit("counter.cleared", data)` in a handler | `Jido.Agent.Directive.emit/2` | It returns data and sends nothing. With no other destination, the Signal goes back to the same Agent as a new Turn. | [Life of a Signal](signal-to-effects.md) |
| `await fetch(...)` inside the update | I/O inside an Action | It runs before commit. If the Turn fails later, the request was still sent. | [Errors and Async](errors-and-async.md) |
| An effect result fed back into the reducer | Emit a Signal back to the Agent | A Directive returns nothing to the Action. The `call/3` reply confirms the commit, not the effects. Read `last_effect_outcome` from `status/2`. | [Life of a Signal](signal-to-effects.md) |
| A custom effect handler | A Plugin-owned Directive with `dispatch/4` | The Plugin must declare the Directive type in `directives/1`. Two Plugins can't own the same type. | [Custom Directives](plugin-custom-directives.livemd) |

## Middleware

A Plugin is the closest thing to request middleware. It runs callbacks around
every Turn but can't replace the Signal or the selected route.

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| Middleware `(req, next)` that enriches a request | `prepare/2` | Plugins run in declaration order. Output goes to `context.plugin_inputs[Plugin].prepared`. It can't change the Signal, the caller context, or the route. | [Extensions or Plugins](extensions-and-plugins.md) |
| Auth or rate-limit middleware that rejects a request | `admit/3` | Runs on a live Server only. `cmd/3` skips it, so test it live. | [Extensions or Plugins](extensions-and-plugins.md) |
| Middleware with its own counter | `state_spec/1` and `reduce/2` | Each Plugin owns one state field. An Action that changes that field fails the Turn. | [Stateful Plugins](write-a-stateful-plugin.livemd) |
| A response-finished hook | `after_commit/3` | Runs after commit and after the `call/3` reply. A failing hook stops later hooks and all Directives. The commit stands. | [Extensions or Plugins](extensions-and-plugins.md) |
| A decorator that attaches metadata | An Extension: `use Jido.Agent.Extension` | Data only. No Extension code runs during a Turn. | [Extensions or Plugins](extensions-and-plugins.md) |
| Middleware that holds a connection pool | `child_spec/1` | Starts one supervised runtime per Agent activation, not one per app. | [Extensions or Plugins](extensions-and-plugins.md) |

## Events

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| An event name string on an `EventEmitter` | A Signal `type`, such as `"counter.increment"` | A Signal is a CloudEvents struct with `id`, `source`, and `data`, not a bare payload. | [Life of a Signal](signal-to-effects.md) |
| `emitter.on(type, handler)` | `route "counter.increment", MyApp.Increment` | One handler per Signal: the first matching route wins. No fan-out. No match fails the Turn with `"No route accepts this Signal type"`. | [Routes and Handlers](build-agent-routes.livemd) |
| A wildcard listener | `route "counter.*", ...` | `*` matches one segment. `"counter.a.b"` needs `"counter.**"`. A wildcard route can't take `as:`. | [Routes and Handlers](build-agent-routes.livemd) |
| An event creator `increment(amount)` | `increment_signal!/2`, generated by `as: :increment` | It sets `type` and `source`. It doesn't check `data`; the Action schema does, during the Turn. | [Routes and Handlers](build-agent-routes.livemd) |
| A discriminated union checked by Zod | An Action input schema on one exact route | The route selects by Signal type. The Action schema validates data during the Turn. | [Types and Validation](types-and-validation.md) |
| `await` a request-response call | `call/3`, or `submit/3` then `await/2` | `call/3` returns after commit. A caller timeout doesn't cancel the Turn. | [Call, Cast, and Await](send-signals-to-live-agents.livemd) |
| Fire-and-forget `emit` | `cast/3` | Returns before the Turn runs. Queued Signals aren't durable. | [Call, Cast, and Await](send-signals-to-live-agents.livemd) |
| App-wide pub/sub | `Jido.Signal.Bus` with the `Bus.Manager` and `Bus.Client` Plugins | The bus lives as long as the Agent that manages it. Each delivered Signal runs a normal Turn on the subscriber. | [Signal Bus](signal-bus-plugin.livemd) |
| Piping one component's events into another | Topology connections | An emitted Signal with no matching connection is dropped, and the effect still reports `:succeeded`. | [Connect Agent Outputs](connect-agent-outputs.livemd) |

## Background Work

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| `setInterval(fn, ms)` | `Jido.Plugin.Heartbeat` (`interval` default 5,000 ms) | Each tick is a cast that runs a full Turn and needs a route. Slow Turns queue ticks up to `max_postponed_signals` (1,000), then the Server drops them. | [Heartbeats and Schedules](heartbeats-and-schedules.livemd) |
| `setTimeout(fn, ms)` | `Jido.Plugin.Scheduler.schedule/2` Directive | It's not in Agent state. It is lost if the Scheduler process stops. | [Heartbeats and Schedules](heartbeats-and-schedules.livemd) |
| A cron job in a job queue | `Jido.Plugin.Scheduler.cron/4` | Stored in `scheduler.cron`. Survives a restart only with persistence. Missed slots aren't replayed. | [Heartbeats and Schedules](heartbeats-and-schedules.livemd) |
| A durable job queue with retries | No equivalent | Queued Signals, `call/3` waits, and Directives aren't stored. Use an external job system for work that must run. | [Durability Model](durability-model.md) |
| A durable workflow engine with steps and waits | A routed `Jido.Flow` on an Agent with persistence | A checkpoint is saved after each step. A step that was running during a crash runs again. The default `turn_timeout:` (60,000 ms) includes wait time. | [Durable Turns and Flows](durable-turns-and-flows.livemd) |
| `AbortController` | `cancel_turn/3`, `admission_timeout:` | Cancellation stops owned work before commit. During `:saving`, it returns `{:error, :commit_in_progress}`. | [Admission and Deadlines](agent-server-admission.md) |
| `worker_threads` | One BEAM process per Agent | No shared memory. Messages are copied. The BEAM schedules processes on every core. | [Node.js and the BEAM](nodejs-and-the-beam.md) |

## App Structure

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| A DI container or app context | A Jido instance: `use Jido, otp_app: :my_app` | It's a supervisor in your tree with its own registry and task supervisor. Nothing is injected; you call `MyApp.Jido.start_agent/2`. | [Instances and Tenants](configuration-and-tenant-isolation.md) |
| A service locator | `MyApp.Jido.whereis_agent/1` | Lookup is by Agent ID. `start_agent` needs `id:`; without it, it fails with `:invalid_string`. | [Start and Address Agents](start-and-address-live-agents.livemd) |
| Tenant scoping on a request context | `namespace:` and partitions | A partition separates IDs and storage keys, not tasks or schedulers. It isn't authorization; check access before you route a Signal. | [Instances and Tenants](configuration-and-tenant-isolation.md) |
| A process manager that restarts a crashed app | Supervisors | Without persistence, a restarted Agent is back at its initial state and revision 0. Persistence is off unless you pass `persistence: :inherit`. | [Supervision and Lifecycle](agent-activation-control.md) |
| `process.env` and a config module | `config :my_app, MyApp.Jido` in `config/runtime.exs` | An unknown key stops the instance at startup. | [Instances and Tenants](configuration-and-tenant-isolation.md) |
| `package.json` and npm | `mix.exs` `deps/0`, Hex, `mix deps.get` | `mix.lock` pins every dependency. Dependencies are compiled into your project. | [Getting Started](getting-started.livemd) |

## Testing

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| A unit test of a reducer | `cmd/3` in an ExUnit test | No process is started and Directives come back as data. I/O inside an Action still runs. | [Testing](test-jido-systems.livemd) |
| A spy on the effect layer | Assert on the returned Directives, or set `default_dispatch: {:pid, target: self()}` and `assert_receive` | `cmd/3` doesn't run `admit/3`, `after_commit/3`, or Directives. Test those on a live Server. | [Testing](test-jido-systems.livemd) |
| A test runner with mocks and isolated workers | ExUnit with `async: true` and one Jido instance per test via `start_supervised/1` | ExUnit has no built-in module mocks. Named instances shared across async tests collide. | [Testing](test-jido-systems.livemd) |
| `await sleep(100)` before an assertion | `assert_receive` or a bounded poll | Fixed sleeps make flaky tests. | [Testing](test-jido-systems.livemd) |
| Fake timers | `cmd/3` on a `cron/4` Action, or the Scheduler `time_scale:` option | `cmd/3` shows the schedule in state but starts no timer. | [Heartbeats and Schedules](heartbeats-and-schedules.livemd) |

## Tooling

| In TypeScript | In Jido | Where it breaks | Guide |
| --- | --- | --- | --- |
| The Node REPL | `iex -S mix` | `recompile/0` reloads changed modules without a restart. | [Getting Started](getting-started.livemd) |
| A notebook | Livebook | `plugin` works in a cell. Use `extensions: [...]` when a provider adds custom Spark sections or needs no config. | [Extensions or Plugins](extensions-and-plugins.md) |
| `tsc --noEmit` | `mix compile --warnings-as-errors` | You write no type annotations. The compiler infers types and warns on violations it can prove. Jido checks route targets and Plugin shapes at compile time. Zoi checks data at runtime. | [Types and Validation](types-and-validation.md) |
| A stricter type checker | Dialyzer (`mix dialyzer`) | It reports only errors it can prove. The first run builds a PLT and takes minutes. | [Types and Validation](types-and-validation.md) |
| A linter and formatter | Credo (`mix credo`) and `mix format` | `mix format` ships with Elixir. Credo is a dev dependency. | [mix format](https://hexdocs.pm/mix/Mix.Tasks.Format.html) |
| An inspector attached to a running server | Remote IEx: `iex --remsh` on a live node | You run code on the production node. `Jido.AgentServer.status/2` and `history/1` are safe reads. | [Observability](observe-agent-turns.livemd) |
| Logs and traces | `Jido.Telemetry` events and metrics | Turn summaries hold IDs, status, and revisions, never Signal data or state. | [Observability](observe-agent-turns.livemd) |

## Next

- [Types and Validation](types-and-validation.md) – Zoi schemas where you
  used TypeScript types and Zod.
- [Errors and Async](errors-and-async.md) – structured errors and Turns where
  you used exceptions and promises.
