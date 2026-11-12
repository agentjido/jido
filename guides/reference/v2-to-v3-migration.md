# V2 to V3 Migration

This guide moves an application from the Jido V2 packages to the consolidated V3 `:jido` package. It lists each V2 surface and its replacement, starting with the changes that break the most code. V3 has no compatibility mode, no automatic code rewrite, and no automatic conversion of stored V2 data.

Old module names that no longer exist are written in plain text. Current names are in code font.

## What was compared

| V2 package | Version checked |
| --- | --- |
| `jido` | `2.4.0` |
| `jido_action` | `2.3.2` |
| `jido_signal` | `2.3.2` |
| `jido_ai` | `2.4.0` |

The V3 side is this package. For the move from the split V3 betas, see [Package Consolidation](consolidated-package-migration.md). Its dependency, application, and configuration sections also apply to you, because V3 merges all four packages. Replace `Zoi.` with `Jido.Joi.` in V3 code, as that guide explains.

Port one small Agent end to end before you change the rest, and run your tests after each section.

## The changes that break the most code

| V2 | V3 |
| --- | --- |
| `MyAgent.new(opts)` returns an Agent | `MyAgent.instantiate(opts)` returns `{:ok, agent}`. `instantiate!/1` raises. |
| `schema: [count: [type: :integer]]` in `use Jido.Agent` | `schema Jido.Joi.object(...)` in a `state do` block |
| `signal_routes: [{"type", Action}]` | `route "type", Action` in a `routes do` block |
| `cmd(agent, Action)` or `cmd(agent, {Action, params})` | `cmd(agent, signal)`. Only a `Jido.Signal` is accepted. |
| `{agent, directives} = cmd(...)` | `{:ok, candidate, directives}`, `{:handoff, candidate, instruction, directives}`, or `{:error, reason}` |
| An Action returns a partial state map | An Action on an Agent route returns the complete next state |
| `{:ok, agent} = AgentServer.call(server, signal)` | `{:ok, agent, directives} = Jido.AgentServer.call(server, signal)` |
| `AgentServer.call("agent-id", signal)` | Pass a PID or a server name. A string raises `FunctionClauseError`. |
| Strategies, `on_before_cmd/2`, `on_after_cmd/3` | Removed. Use Actions, Flows, and Plugin callbacks. |
| `use Jido.Plugin, name: ..., state_key: ..., schema: ...` | `use Jido.Plugin` plus callbacks such as `c:Jido.Plugin.state_spec/1` and `c:Jido.Plugin.reduce/2` |
| `use Jido, otp_app: ..., storage: ...` | `use Jido, otp_app: ..., namespace: ..., persistence: ...` |
| `MyApp.Jido.start_agent(agent)` | `Jido.start_agent(MyApp.Jido, agent)` |
| `use Jido.Action, category: ..., tags: ..., vsn: ...`, NimbleOptions schemas | `name`, `description`, `schema`, and `output_schema`. Schemas use `Jido.Joi`. |
| `max_retries: n` on `Jido.Exec.run/4` | `max_attempts: n + 1` |
| `Jido.Instruction.new!(action: Mod)` | `Jido.Instruction.new!(target: Mod)` |

## Agent modules

V2 put the schema and routes in `use Jido.Agent` options. V3 puts them in blocks, and the schema must be static.

```elixir
defmodule MigrationGuide.Increment do
  use Jido.Action,
    name: "increment",
    schema: Jido.Joi.object(%{amount: Jido.Joi.integer()})

  @impl true
  def run(%{amount: amount}, %{agent_state: state}) do
    {:ok, %{state | count: state.count + amount}}
  end
end

defmodule MigrationGuide.PartialIncrement do
  use Jido.Action,
    name: "partial_increment",
    schema: Jido.Joi.object(%{amount: Jido.Joi.integer()})

  @impl true
  def run(%{amount: amount}, _context), do: {:ok, %{count: amount}}
end

defmodule MigrationGuide.Counter do
  use Jido.Agent, name: "migration_counter"

  state do
    schema Jido.Joi.object(%{
             count: Jido.Joi.integer() |> Jido.Joi.default(0),
             status: Jido.Joi.atom() |> Jido.Joi.default(:idle)
           })
  end

  routes do
    signal_source "/my_app/counter"
    route "counter.increment", MigrationGuide.Increment, as: :increment, defaults: %{amount: 1}
    route "counter.partial", MigrationGuide.PartialIncrement, as: :partial
  end
end

{:ok, agent} = MigrationGuide.Counter.instantiate(id: "counter-1", state: %{count: 10})
```

| V2 | V3 |
| --- | --- |
| `new/1` | `instantiate/1` and `instantiate!/1`. There is also `Jido.Agent.instantiate/2`. |
| `schema:` option | A `state` block |
| `signal_routes:` option, `signal_routes/1` callback | A `routes` block, and `route_add/3` and related Directives at runtime |
| `category`, `tags`, `max_state_size` options | Not V3 options. Keep descriptive data in `metadata:`. |
| `schedules:`, `default_plugins:` options | The `Jido.Plugin.Scheduler` Plugin, and explicit `plugins` |
| A struct with `id` and `state` always set | Two forms. A definition has `id: nil` and `state: nil`. An instance has a nonempty `id` and validated state. |

Keep PIDs, references, connections, and timers out of Agent state. See [Define an Agent](../agents/define-and-instantiate-an-agent.livemd) and [Agent State and Schemas](../agents/agent-state-and-schemas.md).

## Commands and results

V2 `cmd` accepted an Action module, an `{Action, params}` tuple, an Instruction, or a list. V3 `cmd/3` accepts one Signal. The Signal's route selects one Action or Flow.

An Action on an Agent route now returns complete state, read from `context.agent_state`. A partial map fails validation.

```elixir
signal = MigrationGuide.Counter.increment_signal!(%{amount: 2})

{:ok, candidate, []} = MigrationGuide.Counter.cmd(agent, signal)
%{count: 12, status: :idle} = candidate.state

{:error, %Jido.Error.ValidationError{message: "State does not match its schema"}} =
  MigrationGuide.Counter.cmd(agent, MigrationGuide.Counter.partial_signal!(%{amount: 2}))

{:error, %Jido.Error.ValidationError{message: "No route accepts this Signal type"}} =
  MigrationGuide.Counter.cmd(agent, Jido.Signal.new!("counter.reset", %{}, source: "/my_app"))

unsupported =
  try do
    MigrationGuide.Counter.cmd(agent, MigrationGuide.Increment)
  rescue
    error -> error.__struct__
  end

FunctionClauseError = unsupported
```

| V2 | V3 |
| --- | --- |
| Jido.Agent.StateOp, StateOps | Removed. Build the complete map. |
| A list of Actions in one `cmd` | A [Flow](../flows/flows.md) route. Its result commits once. |
| Checking for an error Directive | Match `{:error, reason}` |
| `{agent, directives}` | See [State and Directives](../agents/agent-results-and-directives.md) |

`Jido.Agent.set/2` remains. It replaces top-level domain fields and validates the result.

## Routes

| V2 `signal_routes` entry | V3 route |
| --- | --- |
| `{"user.created", MyAction}` | `route "user.created", MyAction` |
| `{"payment.*", match_fun, MyAction, 10}` | `route "payment.*", MyAction`. Put the check in the Action or a Plugin `c:Jido.Plugin.admit/3`. |
| Plugin-supplied routes | Declare each route on the Agent |

Jido checks routes in declaration order and runs the first match. See [Routes and Handlers](../agents/build-agent-routes.livemd).

## Live Agents

`Jido.AgentServer` runs one Turn at a time and commits state before it runs Directives.

```elixir
{:ok, _} = Jido.start_link(name: MigrationGuide.Jido, namespace: "migration-guide/agents", persistence: {Jido.Persistence.ETS, table: :migration_guide})

{:ok, pid} = Jido.start_agent(MigrationGuide.Jido, MigrationGuide.Counter, id: "counter-2")
^pid = Jido.whereis_agent(MigrationGuide.Jido, "counter-2")

{:ok, %{state: %{count: 2}}, []} =
  Jido.AgentServer.call(pid, MigrationGuide.Counter.increment_signal!(%{amount: 2}))

%{state: %{count: 2}} = Jido.AgentServer.snapshot(pid).agent

pending = Jido.AgentServer.submit(pid, MigrationGuide.Counter.increment_signal!(%{amount: 1}))
{:ok, %{state: %{count: 3}}, []} = Jido.AgentServer.await(pending)
```

| V2 | V3 |
| --- | --- |
| `Jido.AgentServer.call/3` returns `{:ok, agent}` | `{:ok, agent, directives}`. It confirms the commit, not that Directives finished. |
| `call("agent-id", signal)` | Find the PID with `Jido.whereis_agent/3`, or use a Ref with `Jido.call/4` |
| `state(server)` | `Jido.AgentServer.agent/2` for the Agent, `Jido.AgentServer.status/2` for runtime state, `Jido.AgentServer.snapshot/2` for both from one event |
| `await_completion/2`, Jido.Await | `Jido.AgentServer.submit/3` and `Jido.AgentServer.await/2` for one Turn |
| `stream_status/2`, `recent_events/2` | Start with `debug: true`, then read `Jido.AgentServer.history/1` |
| `set_debug/2`, Jido.debug, Jido.Debug | The `:debug` AgentServer option for history, and the `:debug` instance option for logs. A hidden `set_debug/2` on `Jido.Telemetry` changes log detail for persistence events at run time. |
| `whereis(registry, id)`, `via_tuple/2` | `Jido.whereis_agent/3` or `Jido.AgentServer.whereis/3` |
| `MyApp.Jido.whereis(id)` | `Jido.whereis_agent(MyApp.Jido, id)` |
| `attach/2`, `detach/2`, `touch/1` | Kept. `Jido.AgentServer.attach/3` and `Jido.AgentServer.detach/3` add a timeout. |
| `adopt_child/4`, `stop_child/3` | Kept on `Jido.AgentServer` |
| Jido.AgentServer.State and `:sys.get_state` | `Jido.AgentServer.agent/2`, `Jido.AgentServer.status/2`, `Jido.AgentServer.snapshot/2`, and `Jido.AgentServer.children/2` |

A caller timeout does not cancel a Turn. Use `Jido.AgentServer.cancel/2` or `Jido.AgentServer.cancel_turn/3`. See [Call, Cast, and Await](../agent-servers/send-signals-to-live-agents.livemd).

## Strategies and hooks

Jido.Agent.Strategy, the Direct and FSM strategies, `on_before_cmd/2`, and `on_after_cmd/3` are removed.

| V2 responsibility | V3 location |
| --- | --- |
| Domain logic and branching | An Action or Flow |
| FSM states and transitions | The `Jido.Agent.Plugin.FSM` Plugin, or a field changed by Actions |
| Input checks before a command | An Action schema, or `c:Jido.Plugin.prepare/2` |
| Checks that need live resources | `c:Jido.Plugin.admit/3` |
| Updates after each command | `c:Jido.Plugin.reduce/2`, on the field the Plugin owns |
| Work after commit | A Directive |

## Plugins

V3 selects Plugin behavior from the callbacks you define.

```elixir
defmodule MigrationGuide.TurnCounter do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:turns, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end

defmodule MigrationGuide.Tracked do
  use Jido.Agent, name: "migration_tracked", plugins: [MigrationGuide.TurnCounter]

  routes do
    signal_source "/my_app/tracked"

    route "tracked.touch", as: :touch do
      action %{}, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

tracked = MigrationGuide.Tracked.instantiate!(id: "tracked-1")
{:ok, %{state: %{turns: 1}}, []} = MigrationGuide.Tracked.cmd(tracked, MigrationGuide.Tracked.touch_signal!(%{}))
```

| V2 Plugin surface | V3 replacement |
| --- | --- |
| `name:`, `state_key:`, `schema:` options | `c:Jido.Plugin.state_spec/1` returns `{key, schema}` |
| `mount/2` | A schema default for state, and `c:Jido.Plugin.child_spec/1` for processes |
| `actions:`, `signal_routes:`, `signal_routes/1` | Declare routes on the Agent |
| `subscriptions/2` | `Jido.Plugin.Bus.Client` or a managed sensor |
| `handle_signal/2` | `c:Jido.Plugin.admit/3` can reject. It cannot change the selected route. |
| `prepare_signal/2` | `c:Jido.Plugin.prepare/2` |
| `prepare_action/3` | Removed. Use the Action schema. |
| `prepare_emit/2` | `c:Jido.Plugin.prepare_outbound/4` |
| `transform_result/3` | `c:Jido.Plugin.reduce/2`, for the Plugin's own field only |
| `child_spec(config)` | `c:Jido.Plugin.child_spec/1`, which receives a `Jido.Plugin.Init` |
| `on_checkpoint/2`, `on_restore/2` | `c:Jido.Plugin.dump/3` and `c:Jido.Plugin.load/3` |
| Jido.Plugin.Instance, Requirements, Routes, Schedules | Removed |

See [Plugin Design](../plugins/plugin-design.md).

## Directives

| V2 (Jido.Agent.Directive) | V3 |
| --- | --- |
| `emit(signal, dispatch)` | `Jido.Agent.Directive.emit/2` |
| `emit_to_pid(signal, pid)` | `Jido.AgentServer.Directive.signal_send/3` |
| `emit_to_parent(agent, signal)` | `Jido.Agent.Directive.parent_send/1` |
| `error(error, context)` | `Jido.AgentServer.Directive.error_report/2` |
| `spawn(child_spec, tag)` | `Jido.AgentServer.Directive.process_start/1` |
| `spawn_agent(agent, tag, opts)` | `Jido.AgentServer.Directive.agent_start/3`, or a topology member |
| `stop_child(tag, reason)` | `Jido.AgentServer.Directive.agent_stop/2` |
| `stop(reason)` | `Jido.Agent.Directive.server_stop/1` |
| `start_sensor/3`, `stop_sensor/2` | `Jido.Plugin.SensorManager.start/3`, `Jido.Plugin.SensorManager.stop/1` |
| `schedule(delay_ms, message)` | `Jido.Plugin.Scheduler.schedule/2` |
| `cron(expr, message, opts)` | `Jido.Plugin.Scheduler.cron/4` |
| `cron_cancel(job_id)` | `Jido.Plugin.Scheduler.cancel/1` |
| `run_instruction/2` | Removed. Route a Signal to an Action or Flow. |
| The Jido.AgentServer.DirectiveExec protocol | A Plugin that owns the Directive and implements `c:Jido.Plugin.dispatch/4` |

The Server validates the whole batch before commit and runs it after commit. A failed Directive stops the rest of the batch and does not undo the commit. See [Runtime Effects](../agent-servers/runtime-directives-and-effects.md).

## Sensors, schedules, pods, and pools

| V2 | V3 |
| --- | --- |
| Jido.Sensor, `init/2`, `handle_event/2`, `terminate/2` | Any module with `child_spec/1`, run by `Jido.Plugin.SensorManager`. See [Managed Sensors](../built-in-plugins/managed-sensors.livemd). |
| Jido.Sensors.Heartbeat | `Jido.Plugin.Heartbeat`. See [Agent Heartbeats](../built-in-plugins/heartbeats.livemd). |
| Jido.Scheduler, the Agent `schedules` option | `Jido.Plugin.Scheduler`. See [Schedules](../built-in-plugins/scheduler.livemd). |
| Jido.Pod and its mutation API | The static Agent `topology` block for fixed members, or explicit AgentServer child operations for dynamic children. See [Declare Agent Topology](../composition/declare-agent-topology.livemd). |
| Jido.Agent.WorkerPool, Jido.Agent.InstanceManager | Topology members, or your own bounded workers. V3 has no checkout pool. |

## Persistence

V2 configured storage on the instance. V3 needs a stable namespace and an adapter, and each Agent opts in.

```elixir
{:ok, durable} = Jido.start_agent(MigrationGuide.Jido, MigrationGuide.Counter, id: "counter-3", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(durable)

{:ok, %{state: %{count: 5}}, []} =
  Jido.AgentServer.call(durable, MigrationGuide.Counter.increment_signal!(%{amount: 5}))

:ok = Jido.hibernate(MigrationGuide.Jido, durable)

{:ok, thawed} = Jido.thaw(MigrationGuide.Jido, MigrationGuide.Counter, "counter-3")
:ok = Jido.AgentServer.await_ready(thawed)
%{state: %{count: 5}} = Jido.AgentServer.snapshot(thawed).agent
```

| V2 | V3 |
| --- | --- |
| Jido.Storage.ETS, File, Redis | `Jido.Persistence.ETS`, `Jido.Persistence.File`, `Jido.Persistence.Redis`. See [Persistence Matrix](persistence-adapter-matrix.md). |
| Jido.Persist, `hibernate(agent)`, `thaw(module, key)` | `Jido.hibernate/3` with the live server, and `Jido.thaw/4` |
| A default of `{Jido.Storage.ETS, table: :jido_storage}` | No default. An instance has no store until you set `:persistence`. |
| Plugin `on_checkpoint/2`, `on_restore/2` | `c:Jido.Plugin.dump/3`, `c:Jido.Plugin.load/3` |
| Jido.Thread.Store and its adapters, Jido.Thread.Plugin, Jido.Memory | `Jido.Thread` and `Jido.Session` are values that you keep in Agent state. See [Sessions and Threads](../data/sessions-and-threads.md). |

V3 has no reader for V2 records. To keep stored Agents:

1. Stop V2 writers and back up the store.
2. Load each record with V2 code and export its ID and state.
3. Convert the state to the V3 schema, including Plugin-owned fields.
4. Build a V3 instance and save it with `Jido.Persistence.save_agent/3` to an empty target store.
5. Restore a sample with `Jido.thaw/4` and check it before cutover.

Do not run V2 and V3 writers against the same records. See [Durability Model](../durability/durability-model.md).

## Actions and execution

```elixir
defmodule MigrationGuide.CreateOrder do
  use Jido.Action,
    name: "create_order",
    description: "Creates an order",
    schema: Jido.Joi.object(%{customer_id: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{order_id: Jido.Joi.string()})

  @impl true
  def run(%{customer_id: customer_id}, _context), do: {:ok, %{order_id: "order-#{customer_id}"}}
end

instruction =
  Jido.Instruction.new!(
    target: MigrationGuide.CreateOrder,
    params: %{customer_id: "42"},
    metadata: %{id: "create-1"}
  )

{:ok, %{order_id: "order-42"}} =
  Jido.Exec.run(instruction, %{}, %{}, timeout: 5_000, max_attempts: 2, backoff: :exponential, base_delay_ms: 50, max_delay_ms: 500)

{:error, %Jido.Error.ValidationError{message: "Removed Instruction fields are not supported"}} =
  Jido.Instruction.new(action: MigrationGuide.CreateOrder)

{:error, %Jido.Error.ValidationError{message: "unknown execution options"}} =
  Jido.Exec.run(MigrationGuide.CreateOrder, %{customer_id: "42"}, %{}, max_retries: 3)
```

| V2 | V3 |
| --- | --- |
| `category`, `tags`, `vsn`, `compensation` Action options | Removed |
| `on_after_validate_params/1`, `on_before_validate_output/1`, `on_after_validate_output/1`, `on_after_run/1`, `on_error/4` | Removed. Only `c:Jido.Action.on_before_validate_params/1` remains. |
| `{:ok, result, extra}` with any third value | The third element must be a list of effect requests |
| A non-map success value | A map, or `Jido.Action.Output` |
| `to_tool/0`, Jido.Action.Tool, Jido.Tools.* | `authoring_contract/0`, and `Jido.AI` tools. Write your own Actions in place of bundled tools. |
| Instruction `action:`, `id:`, `opts:` | `target:`, `metadata:`, and options passed to `Jido.Exec.run/4` |
| Jido.Instruction.normalize, shorthand tuples, `validate_allowed_actions/2` | Build each Instruction with `Jido.Instruction.new!/1` |
| `timeout:` defaults to a whole-Action limit | `timeout:` defaults to `:infinity` and applies to each attempt |
| `max_retries:` | `max_attempts:`, which includes the first attempt. The default is `1`. |
| `backoff: ms` | `backoff: :none`, `:linear`, `:exponential`, or `:jitter`, with `base_delay_ms:` and `max_delay_ms:` |
| `log_level:`, `telemetry:` options, `:jido_action` config defaults | Removed. Configure Logger and telemetry handlers, and pass options per call. |
| `run_async/4`, `await/2`, `cancel/1` | `Jido.Exec.run/4` in your own supervised Task, `Jido.Durable` for durable work, or `Jido.Exec.compile/2` with direct `Runic.Runner` calls for advanced control. See [Direct Runic Execution](../flow-runtime/managed-execution.md). |
| Your `{Task.Supervisor, name: Jido.Action.TaskSupervisor}` child | Remove it. `Jido.Exec.run/4` owns its execution task. Limit calls in your host when you need run-level admission control. |
| Jido.Plan, Jido.Exec.Chain, Jido.Tools.Workflow, Jido.Tools.ActionPlan | `Jido.Flow`. There is no automatic conversion. See [Flows](../flows/flows.md). |
| Jido.Exec.Closure | A function of your own that calls `Jido.Exec.run/4` |
| Jido.Action.Catalog | `Jido.Catalog` and `Jido.Catalog.Discovery`. They differ in shape. See [Catalog and Discovery](../data/catalog.md). |
| Jido.Exec.Compensation | Removed. Run compensation from the caller. |
| Stored Plans and Instructions | No reader. Convert them with your own code to a `Jido.Flow` or `Jido.Instruction`. |

## Signals

```elixir
signal = Jido.Signal.new!("order.placed", %{"id" => "o-1"}, source: "/orders")
%{source: "/orders", specversion: "1.0"} = signal

{:error, _missing_source} = Jido.Signal.new(%{type: "order.placed"})

json = Jido.Signal.Codec.serialize!(signal)
{:ok, %{type: "order.placed"}} = Jido.Signal.Codec.deserialize(json)

{:ok, _bus} = Jido.Signal.Bus.start_link(name: :migration_guide_bus)
{:ok, [%{cursor: cursor}]} = Jido.Signal.Bus.publish(:migration_guide_bus, [signal])
{:ok, [%{cursor: ^cursor}]} = Jido.Signal.Bus.replay(:migration_guide_bus, "order.*", after: 0, limit: 10)
```

| V2 | V3 |
| --- | --- |
| Jido.Signal.Serialization and its serializers, MessagePack | `Jido.Signal.Codec`. Convert stored MessagePack data before you upgrade. |
| `jido_dispatch` Signal field | Removed. Pass targets to `Jido.Signal.Dispatch`, or `target:` to a Bus subscription. |
| Jido.Signal.Ext and its registry, Jido.Signal.Ext.Trace, Dispatch | A custom Signal module with a schema, and `Jido.Signal.Context` for flat attributes |
| Jido.Signal.Trace, Trace.Context, TraceContext | `Jido.Trace`, `Jido.Signal.Context.put_trace/2`, `Jido.Trace.Context` |
| Jido.Signal.ID | `Jido.Id` |
| `dispatch_async`, `dispatch_batch` | `Jido.Signal.Dispatch.dispatch/2` from your own Task. Retry and rate limits belong to your application. |
| Jido.Signal.Dispatch.CircuitBreaker, ConsoleAdapter, Named, NoopAdapter, Webhook | The `:pid`, `:named`, `:pubsub`, `:bus`, `:logger`, `:noop`, and `:http` adapters, or a custom adapter |
| Custom adapter `validate_opts/1` | `c:Jido.Signal.Dispatch.Adapter.options_schema/0` |
| Jido.Signal.Journal and its adapters, Jido.Signal.Bus.Middleware, Partition, Snapshot | Removed. `Jido.Signal.Bus` has retained replay, durable cursors, and a `Jido.Signal.Bus.Store` boundary. |
| Bus `replay(bus, path, timestamp, opts)` | `Jido.Signal.Bus.replay/3` with `after:` and `limit:` |
| Bus `snapshot_*`, `reconnect/3`, `dlq_entries/2`, `redrive_dlq/3`, `clear_dlq/2` | Removed |
| Jido.Signal.Instance, Names, Util | `Jido.Signal.Bus.via_tuple/2` and `Jido.Signal.Bus.whereis/2` |
| Jido.Signal.BusSpy | Removed. The [Bus events](telemetry-event-reference.md#signal-bus-events) report publishes and deliveries. |

See [Custom Signals](../signals/signals-and-custom-types.md), [Signal Wire Format](../signals/signal-codecs.md), and [Signal Bus](../signals/signal-bus-and-subscriptions.md).

## AI Agents

V2 AI Agents wrapped a ReAct strategy. V3 AI Agents are ordinary Agents whose route runs a reasoning Flow.

```elixir
defmodule MigrationGuide.AddNumbers do
  use Jido.Action,
    name: "add_numbers",
    description: "Add two numbers.",
    schema: Jido.Joi.object(%{a: Jido.Joi.integer(), b: Jido.Joi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{sum: a + b}}
end

defmodule MigrationGuide.MathAgent do
  use Jido.AI.Agent, name: "migration_math_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Solve accurately. Use tools for arithmetic."
    end

    tools do
      action MigrationGuide.AddNumbers
    end
  end
end

Jido.AI.Reasoning.ReAct = MigrationGuide.MathAgent.reasoning()
{:ok, _preflight} = MigrationGuide.MathAgent.preflight(%{input: "What is 19 + 23?"})
%Jido.Signal{type: "jido.ai.request"} = MigrationGuide.MathAgent.request_signal!(%{input: "What is 19 + 23?"})
```

| V2 | V3 |
| --- | --- |
| `use Jido.AI.Agent, model: :fast, tools: [...], system_prompt: "..."` | An `ai do` block with `reasoning` and `tools`, as above |
| `MathAgent.ask_sync(pid, text)` | `Jido.AgentServer.call/3` with `request_signal!/1`. The reply is a Directive. |
| Jido.AI.CoTAgent, CoDAgent, AoTAgent, ToTAgent, GoTAgent, TRMAgent, AdaptiveAgent | `use Jido.AI.Agent` with the matching [reasoning Flow](reasoning-strategy-matrix.md) |
| Jido.AI.Reasoning.*.Strategy, Machine, CLIAdapter | The Flow modules, such as `Jido.AI.Reasoning.ChainOfThought` |
| `config :jido_ai, model_aliases: ...`, Jido.AI.ModelAliases | A model string on each Flow, for example `"openai:gpt-4o-mini"` |
| Jido.AI.Plugins.*, Jido.AI.Directive.*, Jido.AI.Signal.* | Removed. See [Graph-First AI Agents](../ai/graph-first-ai-agents.livemd). |
| Jido.AI.Observe | `Jido.Telemetry.AI` |
| Jido.AI.Actions.LLM.Embed | `Jido.AI.Actions.Embed`. The other Jido.AI.Actions.* modules are removed. |
| Jido.AI.Skill.Registry, Loader, and their error modules | `Jido.AI.Skill` |
| Jido.AI.Test, TestCase | A local `Jido.AI.InferenceClient`. See [Test AI Agents](../ai/testing-ai-agents.livemd). |

## Other removed modules

| V2 module | V3 replacement |
| --- | --- |
| Jido.Agent.Identity | None. Keep identity data in Agent state. |
| Jido.Discovery | `Jido.Catalog.Discovery` |
| Jido.Observe | `Jido.Telemetry` |
| Jido.Telemetry.Config, Formatter | [Configuration Reference](configuration-reference.md#application-config) |
| Jido.ID | `Jido.Id` |
| Jido.Actions.Control, Lifecycle, Scheduling, Status | Your own Actions and the V3 Directives |
| Jido.Util, Jido.Util.DeepMerge, Jido.Igniter.* | None |

The V2 Mix tasks are gone: `mix jido.install`, `mix jido.gen.agent`, `mix jido.gen.plugin`, `mix jido.gen.sensor`, `mix jido_action.install`, `mix jido_action.gen.action`, `mix jido_action.gen.workflow`, and the `mix jido_ai` tasks. Add your instance to your supervision tree by hand.

## Errors

`Jido.Error` keeps `Jido.Error.ValidationError`, `Jido.Error.ExecutionError`, `Jido.Error.RoutingError`, `Jido.Error.TimeoutError`, and `Jido.Error.InternalError`. Errors from Actions, Signals, and Flows use these same structs. A Plugin rejection from `c:Jido.Plugin.prepare/2` or `c:Jido.Plugin.admit/3` can still return your own reason. See [Jido Error Contracts](../data/error-contracts.md).

## Checklist

1. Change the dependency and configuration, using [Package Consolidation](consolidated-package-migration.md).
2. Replace `new/1`, and move schemas and routes to blocks.
3. Change each `cmd` call to a Signal, and each result match.
4. Make each Agent Action return complete state.
5. Update `Jido.AgentServer.call/3` matches, and pass the instance to `Jido` functions.
6. Rewrite strategies, Plugins, Directive constructors, sensors, schedules, and pods.
7. Update Action options, Instructions, and Exec options. Set `timeout:` where V2 relied on its default.
8. Update Signal wire code, Dispatch use, and Bus replay.
9. Rewrite AI Agents as `ai do` blocks.
10. Convert stored data in a test environment before you cut over.

## Related

- [Package Consolidation](consolidated-package-migration.md)
- [Jido Mental Model](../start-here/jido-mental-model.md)
- [Public API Guide](public-api-reference.md)
