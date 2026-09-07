# Upgrade from Jido v2 to v3

This guide covers the change from published Jido `2.3.3` to the local
`3.0.0-beta.1` candidate. The public names remain `Jido.Agent` and
`Jido.AgentServer`. Their contracts have changed. There is no V2 compatibility
mode, automatic code rewrite, or automatic stored-data conversion.

The comparison fixes V2 at commit
[`69f3b405`](https://github.com/agentjido/jido/tree/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2)
and this V3 spike at commit
[`77966b1a`](https://github.com/agentjido/jido/tree/77966b1a). See the
[V2 to V3 API map](api-migration-map.md) for the detailed status and change for
each public module.

The beta version is prepared for evaluation. It is not yet published. A version
number does not mean that release checks have passed. See
[validation and known gaps](#validation-and-known-gaps).

This guide follows the change-by-change structure of the
[Ash 3.0 upgrade guide](https://ash.hexdocs.pm/upgrading-to-3-0.html).
The Jido changes below are based on the
[V2 source](https://github.com/agentjido/jido/tree/v2.3.3) and this candidate.
New features that do not require a V2 code change are outside its scope.

## Estimate the migration work

These are relative work estimates, not elapsed-time estimates. Stored data and
custom runtime behavior can cost more to port than the Agent definitions.

| Area used in V2 | Work | Main change | Completion check |
| --- | --- | --- | --- |
| Agent constructors and result matches | Small | Separate definition from instance; use tagged results | Test every success and failure match |
| NimbleOptions state schemas | Small to medium | Convert to static data schemas | Test defaults, invalid values, and missing fields |
| Direct Actions, Instruction lists, state patches | Medium | Route a Signal to one Action or Flow; return complete state | Verify unchanged fields survive each command |
| Custom Strategy or command hooks | High | Move domain execution to Actions/Flows and policy to Plugins | Test order, rejection, and failure isolation |
| V2 Plugins and custom directives | High | Rewrite callbacks, state ownership, and runtime setup | Test startup, commit, dispatch, restart, and cleanup |
| Worker pools or mutable Pods | High | Use explicit owned workers and static Topology | Test capacity, cancellation, and child failure |
| Stored Agents, Plugin checkpoints, Thread stores | High | Write and rehearse an application data conversion | Restore a backup and reconcile pending work |
| Integrated Memory, Discovery, identity profiles | High | Select an application-owned replacement | Test the behavior the removed API supplied |

## Choose the upgrade order

1. Keep a working V2 revision and a copy of its dependency lock file.
2. Inventory the affected APIs and any stored state.
3. Update dependencies and port one small Agent with a direct command.
4. Port state changes and command error handling.
5. Port Plugins, directives, and live process ownership.
6. Rehearse stored-data conversion separately from the code port.
7. Test application behavior, then review deployment and rollback.

Use a source search to find likely work. Matches are inspection points, not
instructions to replace every name:

```sh
rg -n 'Jido\.(Agent|AgentServer|Instruction|Plugin|Storage|Sensor|Pod|Memory|Discovery)' lib test config
rg -n 'signal_routes|on_before_cmd|on_after_cmd|StateOp|DirectiveExec|directive_handler|InstanceManager|WorkerPool' lib test config
rg -n 'mount|prepare_signal|prepare_action|transform_result|on_checkpoint|on_restore' lib test
```

## Update dependencies and installation

The candidate requires Elixir 1.18 or later. The declared OTP minimum is 27.
Core now requires `jido_action ~> 3.0.0-beta.7` and
`jido_signal ~> 3.0.0-beta.4`.

### What you need to change

For evaluation before publication, point the application at this checkout:

```elixir
{:jido, path: "../jido"}
```

After the package is published, the equivalent Hex requirement will be:

```elixir
{:jido, "~> 3.0.0-beta.1"}
```

Update direct `jido_action` and `jido_signal` constraints if your application
has them. Review the
[Jido Action migration guide](https://github.com/agentjido/jido_action/blob/release/v3/guides/v2-to-v3-migration.md)
as part of the same port. An Action that works alone still needs to satisfy the
complete-state contract when an Agent executes it.

Also review the
[Jido Signal migration guide](https://github.com/agentjido/jido_signal/blob/release/v3/guides/v2-to-v3.md).
Core V3 routes canonical V3 Signals. A correct Agent port can still fail when
the application keeps a V2 Signal constructor, wire map, Router assumption, or
Dispatch option.

Do not assume that a V2 `jido_ai`, `jido_browser`, or custom integration works
with Core V3. Check its Plugin, Strategy, and Server API use. Core examples do
not prove compatibility with those packages.

The Igniter installer and Jido generators are removed. Add your instance module
to your supervision tree explicitly. Keep direct dependencies for packages your
application uses. Core production builds do not supply the example-only
`req_llm` or `dotenvy` dependencies.

## Convert Agent schemas and constructors

V2 module construction returns an Agent directly and accepts keyword schemas:

```elixir
defmodule MyApp.Counter do
  use Jido.Agent,
    name: "counter",
    schema: [count: [type: :integer, default: 0]]
end

agent = MyApp.Counter.new(id: "counter-1")
```

### What you need to change

Use a static data schema. Module `new/1` now returns a tagged result. Use
`new!/1` only where an exception is the intended error path:

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end
end

{:ok, agent} = MyApp.Counter.new(id: "counter-1")
agent = MyApp.Counter.new!(id: "counter-1")
```

A definition is now a neutral `%Jido.Agent{}` with `id: nil` and `state: nil`.
An instance has a nonempty binary ID and validated state. Separate these steps
when using generic construction or the Builder:

```elixir
definition = MyApp.Counter.agent()
{:ok, agent} = Jido.Agent.instantiate(definition, id: "counter-1", state: %{count: 5})
```

Do not pass live process state into a definition. Keep PIDs, references,
connections, and timers in owned runtimes. Review any dynamic schema builders:
V3 requires static schemas and does not provide a schema adapter.

**Check:** test schema defaults and invalid state through the constructor. If you
set `max_state_size`, test the complete state, including Plugin state. The limit
uses external term bytes; it does not establish portability.

## Send Signals and return complete state

V2 direct commands can take an Action or tuple. Actions commonly return a patch,
and the caller receives an Agent/directives pair:

```elixir
{agent, directives} = MyApp.Counter.cmd(agent, {MyApp.Increment, %{amount: 2}})
```

V3 accepts a `Jido.Signal` at the Agent command boundary. Its route must select
exactly one Action or Flow. An Instruction list is not a command batch.

### What you need to change

The following is a complete replacement. The Action preserves the rest of the
state and changes only `count`. The route also generates explicit helpers:

```elixir
defmodule MyApp.Increment do
  use Jido.Action,
    name: "increment",
    schema: Zoi.object(%{amount: Zoi.integer()})

  @impl Jido.Action
  def run(%{amount: amount}, %{agent_state: state}) do
    {:ok, %{state | count: state.count + amount}}
  end
end

defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  agent do
    schema Zoi.object(%{
      count: Zoi.integer() |> Zoi.default(0),
      label: Zoi.string() |> Zoi.default("main")
    })
  end

  routes do
    signal_source "/counter"

    route "counter.increment", MyApp.Increment do
      define :increment, args: [:amount]
    end
  end
end

{:ok, agent} = MyApp.Counter.new(id: "counter-1")
{:ok, signal} = MyApp.Counter.increment_signal(2)
{:ok, candidate, []} = MyApp.Counter.cmd(agent, signal)
# candidate.state == %{count: 2, label: "main"}
# agent.state remains %{count: 0, label: "main"}
```

Replace patch returns such as `{:ok, %{count: next_count}}` with complete state
based on `context.agent_state`. Do not copy V2 StateOps into the new result.
The Action must preserve protected Plugin state keys. The owning Plugin changes
those keys through `update_state/3`.

Replace `signal_routes` with definition routes or the declarative `routes` block.
Move a sequence of Actions into a Flow when it represents one command. A Flow
must also produce complete domain state. Do not split it into separate live
calls if your application requires one commit.

Do not assume that an exact route overrides wildcard matches. Multiple matches
are an error. Plugin preparation currently occurs before route selection, so a
Plugin that changes Signal type can change the selected executable.

**Check:** assert that unrelated fields survive success. Test no-match and
multiple-match Signals. Test every pattern match that used the old two-element
result. Direct failures now return `{:error, reason}`; they are not successful
results with an error directive.

## Separate direct execution from live commit

Direct `cmd` creates a candidate. It does not update a running Agent. The Server
owns serial Turns, validation, commit, and later directive dispatch.

### What you need to change

Use the live API when the application needs a committed result:

```elixir
{:ok, _instance} = Jido.start()
{:ok, server} = Jido.start_agent(MyApp.Counter, id: "counter-1")
{:ok, committed} = MyApp.Counter.increment(server, 2)
# committed.state.count == 2
:ok = Jido.stop_agent(server)
```

`Jido.AgentServer.call/3` also accepts a Signal. Use `send_request/3` and
`receive_response/2` when sending and waiting must be separate. Replace old
await/status facades with the documented readiness, status, and cancellation
APIs. Use `cancel_turn/2` when cancellation must target a specific Turn.

Actions and Flows can perform I/O before commit. A failed Turn preserves the
committed Agent state, but it cannot undo completed external work. Directives
run after commit. Failure stops the rest of that directive batch and leaves
the commit in place. Ordinary directives are not a durable outbox.

**Check:** test Action failure, invalid candidate state, persistence conflict,
and directive failure separately. Check that retries do not duplicate external
work. A successful live call is not proof that all later effects succeeded.

## Replace Strategies and command hooks

V2 Strategy, FSM Strategy, `on_before_cmd/2`, and `on_after_cmd/3` are removed.
The Server no longer exposes the old GenServer State structure.

### What you need to change

| Old responsibility | V3 location |
| --- | --- |
| Domain calculation or branching | Action or Flow |
| State machine domain state | Fields in the Agent schema and explicit transitions |
| Pure input preparation | Plugin `prepare/2` |
| Admission that needs live state or a resource | Plugin `admit/3` |
| Plugin-owned state update | Plugin `update_state/3` |
| Runtime work after commit | Typed Plugin directive and `dispatch/4` |
| Observation | Public snapshots/status and V3 telemetry |

There is no callback-for-callback Strategy adapter. Rebuild behavior around
these boundaries. Use `context.agent_id`, `context.agent_state`, and
`context.signal` in Actions instead of private Server fields.

**Check:** verify transition order and failure behavior. Use
`AgentServer.agent/1`, `snapshot/1`, `status/1`, and `children/1` for public
inspection. Remove application dependencies on `:sys.get_state` tuple shapes.

## Rewrite Plugins and custom directives

V2 declares Plugin metadata and state through `use` options, then initializes
state through `mount/2`:

```elixir
defmodule MyApp.CounterPlugin do
  use Jido.Plugin,
    name: "counter_plugin",
    state_key: :counter_plugin,
    schema: Zoi.object(%{turns: Zoi.integer() |> Zoi.default(0)})

  def mount(_agent, _config), do: {:ok, %{turns: 0}}
end
```

### What you need to change

V3 `use Jido.Plugin` takes no options. Declare options on the Agent. Define one
owned state key and its schema with `state_spec/1`:

```elixir
defmodule MyApp.CounterPlugin do
  use Jido.Plugin

  @impl Jido.Plugin
  def state_spec(_opts) do
    {:counter_plugin, Zoi.object(%{turns: Zoi.integer()}) |> Zoi.default(%{turns: 0})}
  end

  @impl Jido.Plugin
  def update_state(state, _directives, _opts) do
    {:ok, %{state | turns: state.turns + 1}}
  end
end
```

Add `plugin MyApp.CounterPlugin` inside the Agent's `agent` block. Use
`plugin MyPlugin, config: [option: value]` for per-Agent options. This example counts
successful candidate reductions; only a successful live commit stores the count.
Set a default on the owned object itself when the key can be absent. A default
on a nested field alone does not create the outer Plugin state object.

Port each capability explicitly:

| V2 surface | Required V3 change |
| --- | --- |
| Manifest, requirements, automatic routes | Declare Plugins and routes on the Agent explicitly |
| `mount/2` | Put portable defaults in the state schema; put runtime setup in an owned child |
| Signal/action preparation hooks | Rewrite against `prepare/2` or `admit/3` and `Jido.Agent.Command` |
| Emit preparation | Use `prepare_dispatch/4` with its Signal context |
| `transform_result/3` | Put domain transformations in the Action/Flow; reduce only owned Plugin state |
| `DirectiveExec` or `directive_handler` | Declare directive types, validate them, and implement `dispatch/4` |
| `child_spec(config)` | Accept `Jido.Plugin.Init`; read configured options from `init.options` |
| Plugin checkpoint/restore hooks | Convert portable owned state through the application persistence contract |

A runtime root must be permanent and owned. Use `Jido.Plugin.state/1` to read
committed owned state after a restart. `Init` does not contain a state snapshot
or state version. `await_ready/2` can wait for reconstruction; readiness failure
stops the owner. A Plugin without a child receives `nil` in `dispatch/4`.

State ownership is not a read-security boundary. A preparation callback can
inspect the Agent in `Jido.Agent.Command`. Later Plugins can change prepared
input. Do not treat the proposed isolation contract as implemented behavior.

**Check:** test owned state protection, callback order, readiness, owner shutdown,
restart reconstruction, and dispatch errors. See
[Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md).

## Port lifecycle and composition

Instance and partition scope remain. V3 uses explicit ownership for child Agents
and runtime resources. V2 InstanceManager, WorkerPool, and mutable Pod APIs are
removed.

### What you need to change

- Replace `Jido.whereis` with `Jido.whereis_agent(id, partition: partition)`
  for the default instance. Use
  `Jido.whereis_agent(instance, id, partition: partition)` only when the
  application selects another Jido instance. Pass the same instance and
  partition to startup, lookup, and persistence.
- Keep `initial_state` for Server startup options. Use `state` for instance
  constructors. Do not rename both options together.
- Use `attach/2`, `detach/2`, and `touch/1` for lifetime control. The default
  `idle_timeout` is `:infinity`.
- Replace pool checkout with explicit bounded owned workers. There is no
  pre-warmed checkout pool.
- Replace Pod definitions with static `Jido.Topology`, owned children, or an
  application-managed group. Arbitrary live graph mutation has no direct port.

A remote disconnect does not prove that a child is dead. Local duplicate
registration checks do not establish exclusive ownership across a cluster.

**Check:** test shutdown, detached owners, idle expiry, worker limits, remote
failure, and cleanup. See
[Agent Server Lifecycle](agent-server-lifecycle.md) and the
[bounded worker example](https://github.com/agentjido/jido/tree/v3-spike/test/examples/05_multi_agent/05_03_bounded_workers).

## Convert stored data explicitly

V2 Storage checkpoints, Plugin pointers, and Thread append stores do not have
an automatic V3 reader. Renaming an envelope is not a conversion.

V3 uses `Jido.Persistence` and a binary adapter with atomic compare-and-swap.
Keys start with `jido:agent:v1:` and include instance, module, partition, and ID.
Restore validates identity, complete state, and recursive portability.

### What you need to change

1. Stop old writers and export a backup with the V2 application.
2. Decode records with the old code. Record the Agent ID, module, partition,
   domain state, Plugin state, history, and pending work.
3. Convert each domain and Plugin state value to the new schemas. Decide how
   to reconcile external work that might already have completed.
4. Construct and validate a V3 instance. Save it through the V3 persistence API
   and adapter. Keep V2 backups separate from V3 records.
5. Restore the saved record in a fresh V3 process. Verify identity, state,
   pending work IDs, retry counts, and Plugin reconstruction before activation.
6. Rehearse rollback. V2 cannot read new records automatically; restoring a
   backup also requires reconciliation of external work performed after cutover.

Do not run old and new writers against the same logical records during this
conversion. There is no general converter for application-specific Plugin
state or external effects.

An uncertain write stops the writer before another Action evaluates. A confirmed
conflict remains a failed commit. Reactivation loads authoritative state.
Without an adapter, RuntimeStore checkpoints survive only local abnormal
restarts while the instance stays alive. They do not survive instance or VM loss.

File storage requires one BEAM owner per directory. Redis TTL remains an adapter
option. `Jido.Thread` and the old Thread stores do not remain. Convert stored
Thread values to application-owned history values before restore.

**Check:** restore a real backup, test stale and uncertain writes, and confirm
that no runtime-only values entered stored state. Definition revision checks,
durable deletion fencing, and live schema upgrades have unmet research tests;
do not use them as migration guarantees. See
[Portable State and Checkpoints](portable-state-and-checkpoints.md) and
[Limits and Performance](limits-and-performance.md).

## Replace other removed interfaces

| V2 feature | Required change and limit |
| --- | --- |
| Sensor behavior, structs, and built-in Sensors | Use explicit input Plugins; SensorManager still needs a callback port |
| Native cron directives and Agent schedules | Use Scheduler/Heartbeat Plugins and explicit occurrence acknowledgement |
| Discovery | Supply explicit modules and a trusted Codec Registry |
| Identity profiles and evolution | Keep policy in the application; there is no profile API adapter |
| Integrated Memory spaces | Model state/history and compaction in the application |
| Thread Agent/Plugin integration | Use application-owned history values and persistence |
| Old observation events/configuration | Port handlers to V3 lifecycle, Turn, commit, directive, and safe error fields |
| Built-in control/status/lifecycle Actions | Use application Actions and supported runtime directives |

**Check:** search the application for each removed interface. Record its
replacement or removal. A module rename alone is not proof of equal behavior.

## Validation and known gaps

Compile and test after each area. For the application port, verify these outcomes:

- Constructors validate state and return the expected result shape.
- Direct and live commands preserve unrelated fields and protect Plugin state.
- Invalid input and failed work leave committed state unchanged.
- Effect retries obey the application's idempotency rules.
- Restart and restore rebuild owned runtimes without losing pending work.
- Remote failure and cancellation do not leak workers or resources.

The default quality check includes core tests, not benchmark or example tests:

```sh
mix quality
```

At the September 7 alpha checkpoint, full runs on Elixir 1.18 / OTP 27 and
Elixir 1.20 / OTP 29 had 11 research failures and one approved exclusion.
Core coverage was 93.9%. These are historical failed full-suite results, not
release approval. The 11 known failing research tests are now temporarily
skipped, with their assertions retained. Example acceptance tests are secondary;
run `mix examples --seed 0` separately when needed. See the
[test policy](https://github.com/agentjido/jido/blob/v3-spike/guides/testing.md).

The unmet research assertions concern route selection, Plugin read/input
isolation, durable namespace identity, definition revisions, durable deletion,
runtime Init snapshots, Turn revision isolation, live state migration, and live
Topology updates. Cluster-exclusive ownership remains unsupported. See the
[acceptance record](https://github.com/agentjido/jido/blob/v3-spike/docs/examples/feature-acceptance-results.md)
and [Test Agents and Plugins](test-agents-and-plugins.livemd).

Before publication, complete the agreed feature scope, repeated test seeds,
recovery and scale checks, runtime matrix, lint, Dialyzer, docs, and fresh package
consumer checks. Documents under `docs/design` are proposals. They do not add
contracts to this beta candidate.
