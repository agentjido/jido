# Limits and Performance

Jido gives each actor a serial Turn boundary. This makes state commits clear,
but it also makes long Turns and unbounded queues visible design risks. Set
limits at the boundaries that your application owns, and measure before you
change them.

## Limit Agent state

Set `max_state_size` in the Agent definition:

```elixir
use Jido.Agent,
  name: "bounded_agent",
  max_state_size: 1_000_000
```

The value is the external term size in bytes for complete state, including
Plugin state. Jido checks the candidate before commit. A `nil` limit avoids the
size calculation.

Keep threads, audit records, pending jobs, deduplication keys, and schedule
occurrences bounded. Large state also increases validation and checkpoint cost.

## Limit actor work

`max_postponed_signals` limits work that reaches an actor while a Turn is active.
The default is `1_000`. Cast is best effort when admission is full. Calls and
requests return an overload result through their normal contracts.

`max_directives_per_turn` limits the Directive list before Jido starts
post-commit work. Its default is `:infinity`. Set a finite value when an Action
or Plugin can create a variable amount of work.

`directive_timeout` limits Plugin and external Directive handling. Its default
is 5 seconds. A caller timeout is a different boundary: the caller can stop
waiting while accepted actor work continues.

## Limit shared execution

A Jido instance Task supervisor has `max_tasks: 1_000` by default. This limit
applies to shared asynchronous Action work. Plugin runtimes and application
workers can have their own concurrency limits.

One actor runs one Turn at a time. To increase domain concurrency, use separate
Agent identities or a bounded worker group when the work can be partitioned.
Do not add concurrency inside one Agent when the operations need one serial
state order.

## Limit topologies

Topology startup defaults are:

| Option | Default |
| --- | --- |
| `:concurrency` | `32` |
| `:ready` | `:all` |
| `:max_agents` | `10_000` |
| `:retry_interval` | `1_000` milliseconds |
| `:task_timeout` | `10_000` milliseconds |

Composition has a limit of 1,000 component scopes and an inclusion depth limit
of 32. Plan expansion checks the configured Agent limit before activation.

## Limit authored documents

Agent and Topology codecs reject unknown or unsafe values and apply document
size, depth, node, and list limits. Treat codec input as configuration data, not
as executable Elixir. Register allowed modules explicitly.

## Measure the correct boundary

Measure Turn duration, Directive duration, queue pressure, state size,
persistence latency, and restore time separately. A slow Directive after commit
has a different effect from a slow Action before commit.

Use semantic telemetry events for production measurements. Use the debug buffer
for short local investigations. The repository example suite and benchmarks
give repeatable shapes, but your state, adapters, and external services define
the production result.
