# Migrating from V2

This guide moves an application from Jido `2.x` (checked against `2.4.0`) to
`3.0.0-beta.2`. The names `Jido.Agent` and `Jido.AgentServer` stay, but their
contracts change. V3 has no compatibility mode, no automatic code rewrite, and
no automatic conversion of stored V2 data.

Jido Action and Jido Signal also change in V3. Port them with their own guides:
[Jido Action migration](https://hexdocs.pm/jido_action/v2-to-v3-migration.html)
and [Jido Signal migration](https://hexdocs.pm/jido_signal/v2-to-v3.html).
This guide covers the `jido` package only.

## The Short Version

These changes break the most V2 code. Fix them first.

| V2 | V3 |
| --- | --- |
| `MyAgent.new(opts)` returns an Agent | `MyAgent.instantiate(opts)` returns `{:ok, agent}`; `instantiate!/1` raises |
| `schema: [count: [type: :integer]]` in `use Jido.Agent` | `schema(Zoi.object(...))` inside a `state do` block |
| `signal_routes: [{"type", Action}]` | `route "type", Action, do: state(:unchanged)` inside a `routes do` block |
| `cmd(agent, Action)` or `cmd(agent, {Action, params})` | `cmd(agent, signal)`; only a `%Jido.Signal{}` is accepted |
| `{agent, directives} = cmd(...)` | `{:ok, candidate, directives}`, `{:handoff, candidate, instruction, directives}`, or `{:error, reason}` |
| Action returns a partial state map | Action returns the complete next state |
| `{:ok, agent} = AgentServer.call(server, signal)` | `{:ok, agent, directives} = AgentServer.call(server, signal)` |
| `AgentServer.call("agent-id", signal)` | Pass a PID or a Ref; a string ID raises `FunctionClauseError` |
| Strategies, `on_before_cmd/2`, `on_after_cmd/3` | Removed; use Actions, Flows, and Plugin callbacks |
| `use Jido.Plugin, name: ..., state_key: ..., schema: ...` | `use Jido.Plugin` plus callbacks such as `state_spec/1` and `reduce/2` |
| `use Jido, otp_app: ..., storage: ...` | `use Jido, otp_app: ..., namespace: ..., persistence: ...` |

Port one small Agent end to end before you change the rest. Compile and run
your tests after each section below.

## Dependencies

V3 requires Elixir 1.18 and OTP 27 or later.

```elixir
def deps do
  [
    {:jido, "~> 3.0.0-beta.2"}
  ]
end
```

Jido beta.2 depends on `jido_action ~> 3.0.0-beta.21`,
`jido_signal ~> 3.0.0-beta.5`, and `runic ~> 0.1.0-alpha.12`. If your
application lists `jido_action` or `jido_signal` directly, move them to the same
versions.

V2 integrations such as `jido_ai` 2.x don't work with Jido V3. Upgrade each one
to its V3 release.

The Igniter installer and the `mix jido.install`, `mix jido.gen.agent`,
`mix jido.gen.plugin`, and `mix jido.gen.sensor` tasks are removed. Add your
Jido instance to your supervision tree by hand.

## Agent Modules

V2 put the schema and routes in `use Jido.Agent` options, and accepted
NimbleOptions keyword schemas:

```elixir
# V2
defmodule MyApp.Counter do
  use Jido.Agent,
    name: "counter",
    schema: [
      count: [type: :integer, default: 0],
      status: [type: :atom, default: :idle]
    ],
    signal_routes: [{"counter.increment", MyApp.Increment}]
end

agent = MyApp.Counter.new(id: "counter-1")
```

V3 takes `name`, `description`, `id`, `vsn`, `metadata`, and `plugins` as
`use` options. Put `plugins` last. The schema goes in a `state` block and must
be a static Zoi schema. Routes go in a `routes` block.

```elixir
# V3
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(0),
        status: Zoi.atom() |> Zoi.default(:idle)
      })
    )
  end

  routes do
    signal_source("/my_app/counter")
    route "counter.increment", MyApp.Increment, as: :increment, defaults: %{amount: 1}
  end
end

{:ok, agent} = MyApp.Counter.instantiate(id: "counter-1", state: %{count: 10})
agent = MyApp.Counter.instantiate!(id: "counter-2")
```

`new/1` no longer exists. V3 also splits the struct into two forms:

- A **definition** has `id: nil` and `state: nil`. `MyApp.Counter.definition()`
  returns it.
- An **instance** has a non-empty `id` and validated state.

Keep PIDs, references, connections, and timers out of Agent state. Put them in
a Plugin runtime. `Jido.Agent.define/1` builds a definition from a plain map. It
doesn't accept a keyword list.

`category`, `tags`, and `max_state_size` aren't V3 Agent options. Put
descriptive data in the `metadata:` option to `use Jido.Agent`.

See [Define an Agent](define-and-instantiate-an-agent.livemd).

## Commands And Results

V2 `cmd/2` accepted an Action module, an `{Action, params}` tuple, an
Instruction, or a list of them, and returned a two-element tuple:

```elixir
# V2
{agent, directives} = MyApp.Counter.cmd(agent, {MyApp.Increment, %{amount: 2}})
```

V3 `cmd/3` accepts one Signal. The Signal's route selects exactly one Action or
Flow. Any other input raises `FunctionClauseError`.

```elixir
# V3
signal = MyApp.Counter.increment_signal!(%{amount: 2})
{:ok, candidate, directives} = MyApp.Counter.cmd(agent, signal)
# candidate.state => %{count: 12, status: :idle}
```

Failures return `{:error, reason}`. V2 code that matched a two-element tuple and
checked for an error Directive must match `{:error, reason}` instead.

A Flow can return a terminal Handoff. Direct `cmd/3` returns
`{:handoff, candidate, instruction, directives}` and does not run the
successor. `AgentServer.call/3` runs the successor as a new Turn and returns
the final normal success or error result.

### Return complete state

A V2 Action could return only the fields it changed. A V3 Agent Action returns
the complete next state. Read the current state from `context.agent_state`:

```elixir
defmodule MyApp.Increment do
  use Jido.Action,
    name: "increment",
    schema: Zoi.object(%{amount: Zoi.integer()})

  @impl true
  def run(%{amount: amount}, %{agent_state: state}) do
    {:ok, %{state | count: state.count + amount}}
  end
end
```

A partial map fails validation with `"State does not match its schema"`. V2
`Jido.Agent.StateOp` and `StateOps` are removed; build the complete map instead.

A V2 list of Actions in one `cmd` call becomes a Flow route. A Flow also
returns complete state, and its result commits once.

`Jido.Agent.set/2` remains. It replaces top-level domain fields and validates
the result. It rejects Plugin-owned fields.

See [State and Directives](agent-results-and-directives.md) and
[Pure or Live Execution](pure-or-live-execution.md).

## Routes

V2 `signal_routes:` took Router tuples, including priorities and inline match
functions. V3 routes are declarations:

| V2 `signal_routes` entry | V3 route |
| --- | --- |
| `{"user.created", MyAction}` | `route "user.created", MyAction, do: state(:unchanged)` |
| `{"payment.*", match_fun, MyAction, 10}` | `route "payment.*", MyAction, do: state(:unchanged)`; put the check in the Action or a Plugin `admit/3` |
| `signal_routes/1` callback | Removed; change routes with `route_add/3` and related Directives |
| Plugin-supplied routes | Declare every route on the Agent |

Jido checks routes in declaration order and runs the first match. A Signal with
no route fails with `"No route accepts this Signal type"`.

V3 adds handlers that V2 didn't have: inline `action` blocks, Flow routes,
transforms, and explicit forwards to named children or the parent. See
[Routes and Handlers](build-agent-routes.livemd).

## Live Agents

The Agent Server is now a `:gen_statem` that runs one Turn at a time and commits
state before it runs Directives.

```elixir
# V2
{:ok, agent} = Jido.AgentServer.call("counter-1", signal, 10_000)

# V3
{:ok, _} = Jido.start()
{:ok, pid} = Jido.start_agent(MyApp.Counter, id: "counter-1")
{:ok, committed, directives} = Jido.AgentServer.call(pid, signal)
```

| V2 | V3 |
| --- | --- |
| `call(server, signal)` returns `{:ok, agent}` | Returns `{:ok, agent, directives}` |
| `call("agent-id", signal)` | Pass a PID; find it with `Jido.whereis_agent/2`, or use a Ref with `Jido.call/4` |
| `state(server)` | `agent/2` for the committed Agent; `status/2` for runtime state |
| `await_completion/2`, `Jido.Await` | Removed; use `submit/3` and `await/2` for one Turn |
| `stream_status/2`, `recent_events/2` | Start with `debug: true`, then read `history/1` |
| `set_debug/2` | `Jido.debug/1` for the instance, or `debug: true` at startup |
| `whereis(registry, id)`, `via_tuple/2` | `Jido.whereis_agent/2` or `AgentServer.whereis/3` |
| `Jido.whereis(id)` | `Jido.whereis_agent(id)` |
| `attach/2`, `detach/2`, `touch/1` | Kept; `attach/3` and `detach/3` add a timeout |
| `adopt_child/4`, `stop_child/3` | Kept on `Jido.AgentServer` |

A successful `call` confirms the commit. It doesn't confirm that Directives
finished; those run after the reply. A caller timeout doesn't cancel the Turn.
Use `cancel/2` or `cancel_turn/3`.

`submit/3` returns a pending handle. Only the process that submitted it can call
`await/2`:

```elixir
pending = Jido.AgentServer.submit(pid, signal)
{:ok, agent, []} = Jido.AgentServer.await(pending)
```

V3 adds admission deadlines, readiness, quiescence, and a separate Turn timeout.
See [Start and Address Agents](start-and-address-live-agents.livemd),
[Call, Cast, and Await](send-signals-to-live-agents.livemd), and
[Admission and Deadlines](agent-server-admission.md).

## Strategies And Hooks

`Jido.Agent.Strategy`, the Direct and FSM strategies, `on_before_cmd/2`, and
`on_after_cmd/3` are removed. Move each responsibility:

| V2 responsibility | V3 location |
| --- | --- |
| Domain logic and branching | An Action or Flow |
| FSM states and transitions | A field in the Agent schema, changed by Actions |
| Input checks before a command | Action schema, or Plugin `prepare/2` |
| Checks that need live resources | Plugin `admit/3` |
| Updates after each command | Plugin `reduce/2` on the field it owns |
| Work after commit | A Directive |

Code that read the V2 `Jido.AgentServer.State` struct or used `:sys.get_state`
must move to `agent/2`, `status/2`, `snapshot/2`, and `children/2`.

## Plugins

V2 configured Plugins through `use` options and `mount/2`:

```elixir
# V2
defmodule MyApp.TurnCounter do
  use Jido.Plugin,
    name: "turn_counter",
    state_key: :turns,
    schema: Zoi.integer() |> Zoi.default(0)

  def mount(_agent, _config), do: {:ok, 0}
end
```

V3 selects Plugin capabilities from the callbacks you define:

```elixir
# V3
defmodule MyApp.TurnCounter do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
```

Declare it in the Agent's `plugins` block with `plugin MyApp.TurnCounter` or
`plugin MyApp.TurnCounter, config: %{...}`. After one successful command the
state includes `turns: 1`.

| V2 Plugin surface | V3 replacement |
| --- | --- |
| `name:`, `state_key:`, `schema:` options | `state_spec/1` returns `{key, schema}` |
| `mount/2` | A schema default for state; `child_spec/1` for processes |
| `actions:`, `signal_routes:`, `signal_routes/1` | Declare routes on the Agent |
| `subscriptions/2` | `Jido.Plugin.Bus.Client` or a managed sensor |
| `handle_signal/2` | `admit/3` can reject; it can't change the selected route |
| `prepare_signal/2` | `prepare/2`; it adds input but can't change the Signal |
| `prepare_action/3` | Removed; use the Action schema |
| `prepare_emit/2` | `prepare_outbound/4` |
| `transform_result/3` | `reduce/2`, for the Plugin's own field only |
| `child_spec(config)` | `child_spec(%Jido.Plugin.Init{})` |
| `on_checkpoint/2`, `on_restore/2` | `dump/3` and `load/3` |

V3 also adds `directives/1`, `dispatch/4`, `after_commit/3`, `await_ready/2`,
`validate_options/1`, `quiesce/2`, and `resume/2`. An Action that changes a
Plugin-owned field fails with `"Agent executable changed Plugin-owned state"`.

See [Agent Plugins](agent-plugins.md),
[Stateful Plugins](write-a-stateful-plugin.livemd),
[Supervised Resources](plugin-supervised-resources.livemd), and
[Plugin Persistence](plugin-persistence-and-live-changes.md).

## Directives

| V2 (`Jido.Agent.Directive`) | V3 |
| --- | --- |
| `emit(signal, dispatch)` | `Jido.Agent.Directive.emit/2`; also `emit("type", data)` |
| `emit_to_pid(signal, pid)` | `Jido.AgentServer.Directive.signal_send(signal, pid, opts)` |
| `emit_to_parent(agent, signal)` | `Jido.AgentServer.Directive.parent_send(signal)` |
| `error(error, context)` | `Jido.AgentServer.Directive.error_report(error, context)` |
| `spawn(child_spec, tag)` | `Jido.AgentServer.Directive.process_start(child_spec)` |
| `spawn_agent(agent, tag, opts)` | `Jido.AgentServer.Directive.agent_start(agent, name, opts)`, or a topology member |
| `stop_child(tag, reason)` | `Jido.AgentServer.Directive.agent_stop(name, reason)` |
| `stop(reason)` | `Jido.AgentServer.Directive.server_stop(reason)`; it must be last |
| `start_sensor/3`, `stop_sensor/2` | `Jido.Plugin.SensorManager.start/3` and `stop/1` |
| `schedule(delay_ms, message)` | `Jido.Plugin.Scheduler.schedule(delay_ms, signal)` |
| `cron(expr, message, opts)` | `Jido.Plugin.Scheduler.cron(job_id, expr, signal, opts)` |
| `cron_cancel(job_id)` | `Jido.Plugin.Scheduler.cancel(job_id)` |
| `run_instruction/2` | Removed; route a Signal to an Action or Flow |
| `Jido.AgentServer.DirectiveExec` protocol | A Plugin that owns the Directive and implements `dispatch/4` |

The Server validates the whole batch before commit and runs it after commit. A
failed Directive stops the rest of the batch. It doesn't undo the commit.

An `Emit` with no destination goes back to the same Agent as a new Turn. Give
emitted Signals a target: `dispatch`, a topology connection, or the Server's
`default_dispatch:` option.

See [State and Directives](agent-results-and-directives.md) and
[Custom Directives](plugin-custom-directives.livemd).

## Sensors And Schedules

`Jido.Sensor`, its `init/2`, `handle_event/2`, and `terminate/2` callbacks, and
the built-in Bus and Heartbeat sensors are removed. In V3:

- A sensor is any module with `child_spec/1`. Run it with the
  `Jido.Plugin.SensorManager` Plugin. It sends input with
  `Jido.AgentServer.cast/3`.
- `Jido.Plugin.Heartbeat` replaces the heartbeat sensor.
- `Jido.Plugin.Bus.Manager` and `Jido.Plugin.Bus.Client` replace the bus
  sensor and Plugin subscriptions.
- `Jido.Scheduler` and the Agent `schedules` option are replaced by the
  `Jido.Plugin.Scheduler` Plugin and its Directives.

See [Managed Sensors](managed-sensors.livemd),
[Heartbeats and Schedules](heartbeats-and-schedules.livemd), and
[Signal Bus](signal-bus-plugin.livemd).

## Pods And Pools

`Jido.Pod` and its mutation API, `Jido.Agent.WorkerPool`, and
`Jido.Agent.InstanceManager` are removed.

- Declare child Agents in the parent's `topology` block. The parent's Agent
  Server starts and supervises them.
- Wire outputs with topology connections, not hard-coded PIDs.
- Change membership with `agent_add/3`, `agent_replace/3`, `agent_remove/1`,
  and the connection Directives. The change commits with the Turn.
- Replace pool checkout with a counted topology member or your own bounded
  workers. V3 has no checkout pool.

See [Composition Vocabulary](composition-vocabulary.md),
[Nested Agents](declare-agent-topology.livemd),
[Connect Agent Outputs](connect-agent-outputs.livemd), and
[Change Live Composition](change-live-composition.md).

## Persistence

V2 configured storage on the instance and saved Agent structs with
`Jido.Persist`:

```elixir
# V2
use Jido, otp_app: :my_app, storage: {Jido.Storage.ETS, table: :jido_storage}
```

V3 needs a stable namespace and an adapter, and each Agent opts in:

```elixir
# V3
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/agents",
    persistence: {Jido.Persistence.ETS, table: :my_app_agents}
end

{:ok, pid} = MyApp.Jido.start_agent(MyApp.Counter, id: "counter-1", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(pid)

:ok = MyApp.Jido.hibernate(pid)
{:ok, pid} = MyApp.Jido.thaw(MyApp.Counter, "counter-1")
:ok = Jido.AgentServer.await_ready(pid)
```

- Pass `persistence: :inherit` to `start_agent`. Without it, the Agent doesn't
  save. `thaw/3` sets it for you.
- A persistent Agent writes revision zero before it accepts Turns. Until then,
  `call` returns `{:error, :not_ready}`. Wait with `await_ready/2`.
- `hibernate/2` now takes the live Server, not an Agent struct.
- Each successful commit is saved before the Server replies.

| V2 | V3 |
| --- | --- |
| `Jido.Storage.ETS`, `File`, `Redis` | `Jido.Persistence.ETS`, `File`, `Redis`; also `Ecto`, `S3`, `Mnesia`, `Bedrock` |
| `Jido.Persist.hibernate/2`, `thaw/3` | Instance `hibernate/2` and `thaw/3` |
| Plugin `on_checkpoint/2`, `on_restore/2` | Plugin `dump/3` and `load/3` |
| `Jido.Thread` and Thread stores | Removed; keep history in Agent state or your own store |

V3 can't read V2 records. To keep stored Agents:

1. Stop V2 writers and back up the store.
2. Load each record with V2 code and export its ID and state.
3. Convert the state to the V3 schema, including Plugin-owned fields.
4. Build a V3 instance and save it with `Jido.Persistence.save_agent/3` to an
   empty target store.
5. Restore a sample with `thaw/3` and check it before cutover.

Don't run V2 and V3 writers against the same records. Downgrade after the first
V3 write isn't supported.

See [Durability Model](durability-model.md),
[Make an Agent Durable](make-an-agent-durable.livemd),
[Storage Model](persistence-storage-model.md), and
[Persistence Adapters](persistence-adapters.livemd).

## Discovery

`Jido.Discovery` is now the shared Authoring Registry from `jido_action`.
Use `list/0`, `list/1`, `get/2`, and `get_by_target/2`. Agent modules and
Plugins publish the same versioned manifests as Actions and Flows. The old
catalog, slug, filter, paging, and timestamp functions are removed.

Discovery does not grant permission to run code. Keep an explicit allowlist
in your application. See [Authoring Discovery and Permission](action-discovery-and-permission.md).

## Removed Modules

| V2 module | V3 replacement |
| --- | --- |
| `Jido.Agent.Strategy` and strategies | Actions, Flows, and Plugin callbacks |
| `Jido.Agent.StateOp`, `StateOps` | Return complete state |
| `Jido.Agent.InstanceManager`, `WorkerPool` | Topology members or your own workers |
| `Jido.Agent.Identity` | None; keep identity data in your Agent state |
| `Jido.Pod` | Agent `topology` block |
| `Jido.Sensor`, `Jido.Sensors.*` | `Jido.Plugin.SensorManager`, `Heartbeat`, `Bus.Client` |
| `Jido.Scheduler` | `Jido.Plugin.Scheduler` |
| `Jido.Storage`, `Jido.Persist` | `Jido.Persistence` and its adapters |
| `Jido.Thread`, `Jido.Memory` | None; model history in your application |
| `Jido.Await` | `Jido.AgentServer.submit/3` and `await/2` |
| `Jido.Observe` | `Jido.Telemetry` |
| `Jido.Actions.Control`, `Lifecycle`, `Scheduling`, `Status` | Your own Actions and the V3 Directives |
| `mix jido.install`, `mix jido.gen.*` | None |

## Errors

`Jido.Error` keeps `ValidationError`, `ExecutionError`, `RoutingError`,
`TimeoutError`, `CompensationError`, and `InternalError`. V3 adds:

- `Jido.Agent.Error` for authoring and routing errors. It has a `code`, a
  `path`, and `details`, for example `"No route accepts this Signal type"`.
- A Plugin error struct for Plugin callback failures. Its module is internal; match on `Exception.message/1`.

Some V3 boundaries still return raw values: a Plugin rejection from `prepare/2`
or `admit/3` returns its own reason, such as `{:error, :actor_required}`, and an
invalid custom Directive returns a list of `Zoi.Error` structs. Match these
shapes explicitly.

## Migration Checklist

- [ ] Dependencies updated; `jido_action` and `jido_signal` ported with their
      own guides.
- [ ] Every `new/1` replaced with `instantiate/1` or `instantiate!/1`.
- [ ] Every schema converted to Zoi inside `state do`.
- [ ] Every `signal_routes` entry moved to `routes do`.
- [ ] Every `cmd` call sends a Signal and matches a normal three-element result,
      a four-element Handoff result, or an error.
- [ ] Every Agent Action returns complete state.
- [ ] Every `AgentServer.call` match updated to `{:ok, agent, directives}`, and
      no call passes a string ID.
- [ ] Strategies and command hooks moved to Actions and Plugin callbacks.
- [ ] Plugins rewritten with V3 callbacks.
- [ ] Directive constructors replaced, and every `Emit` has a destination.
- [ ] Sensors, schedules, pods, and pools moved to Plugins and topology.
- [ ] Persistence configured with a namespace, Agents started with
      `persistence: :inherit`, and V2 records converted and restored in a test
      environment.

See [Testing](test-jido-systems.livemd) for how to test each area.
