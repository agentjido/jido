# V2 to V3 API map

This guide maps the published Jido V2 API to the current V3 spike API. Use it
with [Upgrade from Jido v2 to v3](migration.md). The upgrade guide gives the
recommended work order. This map gives the module-level detail.

The comparison uses two fixed revisions:

- V2 is tag [`v2.3.3`](https://github.com/agentjido/jido/tree/69f3b40506ce3ea1a2c80b255b737d6c3a453cf2),
  commit `69f3b40506ce3ea1a2c80b255b737d6c3a453cf2`.
- V3 is the `v3-spike` revision at commit
  [`77966b1a`](https://github.com/agentjido/jido/tree/77966b1a).

This fixed pair is important. The V3 API can change after this investigation.
Update the V3 commit in this guide before you use the map for a later release.

The inventory uses the compiled module documentation and the source at each
revision. It excludes examples and tests. V2 has 144 modules with visible
module documentation. V3 has 85. Only 38 visible module names occur in both
versions. A shared name does not mean that its contract stayed the same.

Jido Core also depends on Jido Action and Jido Signal. Their APIs are outside
the module count above. Migrate them as part of the same application change:

- [Jido Action V2 to V3 migration](https://github.com/agentjido/jido_action/blob/release/v3/guides/v2-to-v3-migration.md)
- [Jido Signal V2 to V3 migration](https://github.com/agentjido/jido_signal/blob/release/v3/guides/v2-to-v3.md)

## Read the status column

| Status | Meaning |
| --- | --- |
| Same name, new contract | The module exists in both versions, but callers must change. |
| Retained | The main public call shape stays available. Test data and failure behavior again. |
| Replaced | V3 supplies a different module or boundary for the responsibility. |
| Removed | Core V3 has no direct replacement. The application must remove or own the behavior. |
| New | V3 adds a contract that V2 did not have. |
| Private | The name is an implementation detail. Do not build a migration on it. |

## Understand the main boundary changes

| V2 boundary | V3 boundary |
| --- | --- |
| An Agent module creates a ready instance. | An Agent module declares a neutral definition, then creates validated instances. |
| `cmd` accepts Actions, Instructions, or lists. | `cmd` accepts one Signal. A route selects one Action or Flow. |
| An Action result can be a state patch. | The selected executable returns the complete next domain state. |
| A Strategy owns command policy and progress. | Actions and Flows own domain work. Plugins own admission and runtime capabilities. |
| Plugin options declare metadata, routes, schedules, and state. | The Agent declares Plugin options and routes. Each Plugin declares its state and Directive contracts. |
| Server state and status structs expose runtime detail. | Public queries return the Agent, a narrow status, children, Plugin state, or a snapshot. |
| Pods and WorkerPool manage mutable groups. | Topology declares a static system. Application code owns dynamic capacity policy. |
| Storage combines Agent checkpoints and Thread storage. | Persistence stores versioned Agent checkpoints. Thread storage belongs to the application. |

Jido V3 is a declarative actor and agent framework. Code declares an Agent
definition, its data schema, its routes, and its Plugins. The application uses
that definition to create an Agent value or to start a live actor. This is the
center of the migration.

## Map the `Jido` entry module

`Jido` remains the application and instance entry module. Its Agent lifecycle
functions now use the default Jido instance when the caller does not select one.
The explicit instance forms remain for applications that run more than one
Jido supervisor.

| V2 API | V3 API | Change |
| --- | --- | --- |
| `start/1`, `start_link/1`, `stop/1` | Same names | The Jido instance lifecycle remains. Review the new child set and persistence options. |
| `start_agent(instance, agent, opts)` | `start_agent(agent)`, `start_agent(agent, opts)`, or the explicit three-argument form | The default instance is implicit. The Agent argument can be a module, definition, or instance. |
| `stop_agent(instance, pid_or_id, opts)` | `stop_agent(pid_or_id)`, `stop_agent(pid_or_id, opts)`, or the explicit three-argument form | The default instance is implicit. |
| `whereis(instance, id, opts)` | `whereis_agent(id, opts)` or `whereis_agent(instance, id, opts)` | The new name makes the target type explicit. |
| `list_agents(instance, opts)` | `list_agents()`, `list_agents(opts)`, or the explicit instance form | The default instance is implicit. |
| `agent_count(instance, opts)` | `agent_count()`, `agent_count(opts)`, or the explicit instance form | The default instance is implicit. |
| `parent_binding(instance, child_id, opts)` | `agent_parent_binding(child_id, opts)` or the explicit instance form | The new name makes the relationship an Agent relationship. |
| `hibernate(instance, agent, opts)` | `hibernate(server, opts)` or `hibernate(instance, server, opts)` | V3 hibernates the live actor. Do not pass a detached Agent value. |
| `thaw(instance, module, key, opts)` | `thaw(module, agent_id, opts)` or the explicit instance form | V3 restores by Agent identity through the configured persistence contract. |
| `registry_name/1`, `agent_supervisor_name/1`, `task_supervisor_name/1`, `runtime_store_name/1` | Same explicit forms plus zero-argument default forms | Use the zero-argument form for the default instance. |
| `scheduler_name/1` | `Jido.Plugin.Scheduler` | Scheduling is an Agent Plugin, not an instance-wide scheduler facade. |
| `agent_pool_name/2` | No direct replacement | Use explicit Agents, owned children, or an application-owned capacity manager. |
| `alive?/1` | `Jido.AgentServer.alive?/1` | Actor health belongs to the Actor runtime API. |
| `await/3`, `await_all/3`, `await_any/3`, `await_child/4` | `Jido.AgentServer.call/3`, `send_request/3`, `receive_response/2`, and application coordination | A successful call waits for one commit. `await_ready/2` only waits for Plugin runtime readiness. |
| `cancel/2` | `Jido.AgentServer.cancel/2` or `cancel_turn/3` | Use the stable Turn ID when cancellation must not affect a later Turn. |
| `get_child/2`, `get_children/1` | `Jido.AgentServer.children/2` | The public result is a view. Do not depend on private child records. |
| `list_actions/1`, `list_plugins/1`, `list_sensors/1`, `list_demos/1`, the matching `get_*_by_slug/1` calls, and `refresh_discovery/0` | Explicit module references and `Jido.Agent.Codec.Registry` | V3 does not scan and publish an application catalog. |
| `default_instance/0`, `generate_id/0`, `debug/0..2` | Same names | These calls remain. Use public Agent constructors instead of assigning generated IDs by hand when possible. |

## Map Agent modules and generated functions

### `Jido.Agent`

Status: **Same name, new contract**.

The V2 struct stores `agent_module`, `category`, `tags`, `vsn`, one schema, and
state. The V3 struct stores `module`, `max_state_size`, a static domain schema,
ordered Plugin declarations, routes, portable metadata, and optional instance
identity and state.

| V2 API | V3 API | Change |
| --- | --- | --- |
| `new/1` generic constructor creates an instance | `new/1` | Creates and validates a neutral definition. It does not create an instance. |
| `MyAgent.new/1` returns an Agent | `MyAgent.new/1` returns `{:ok, agent}` | Match the tagged result, or use `new!/1` where a raised error is correct. |
| No definition function | `MyAgent.agent/0`, `definition/1`, `definition?/1` | These functions expose the declared, neutral Agent. |
| No explicit instance boundary | `instantiate/2`, `instantiate!/2`, `instance?/1` | Instance creation adds identity and validated complete state. |
| `cmd(agent, action_or_instruction, opts)` returns `{agent, directives}` | `cmd(agent, signal, opts)` returns `{:ok, candidate, directives}` or `{:error, reason}` | Build a Signal and route it to one Action or Flow. |
| `set/2` deep-merges state without full validation | `set/2` merges domain fields and validates the complete next state | Plugin-owned keys are protected. |
| `validate(agent, opts)` | `validate/1`, `validate_definition/1`, `validate_instance/1` | Remove the V2 `:strict` option and select the required value boundary. |
| `schema/0` accepts NimbleOptions or Zoi | `schema/0`, `domain_schema/0`, `complete_schema/0` use static Zoi data schemas | `complete_schema/0` includes Plugin-owned state. |
| No portable Agent map function | `to_map/1` | Use this for a complete portable data view. Use `Jido.Agent.Codec` for an authoring document and `Jido.Persistence` for a checkpoint. |
| `on_before_cmd/2`, `on_after_cmd/3` | `handle_signal/2`, route declarations, and Plugin callbacks | Do not make a callback-for-callback port. Put domain work in Actions or Flows. |
| `signal_routes/0..1` | `routes/0` and the `routes do` block | Routes are part of the Agent definition. |
| `checkpoint/2`, `restore/2` | Same callback names, plus public `checkpoint/2` and `restore/3` functions | The stored envelope and validation contract changed. V2 records are not V3 records. |
| V2 Action patch results | Complete next domain state | Base the result on `context.agent_state` and preserve unrelated fields. |

### Functions generated by `use Jido.Agent`

| V2 generated function | V3 generated function | Change |
| --- | --- | --- |
| `name/0`, `description/0`, `schema/0` | Same names | `schema/0` is now the declared domain data schema. |
| `category/0`, `tags/0`, `vsn/0` | `metadata/0` | Move portable application metadata into the metadata map. |
| `plugins/0`, `plugin_specs/0` | `plugins/0` | V3 returns canonical ordered declarations. The internal Spec is not a public authoring API. |
| `plugin_state(agent, plugin)` | `Jido.AgentServer.plugin_state/3` or a Plugin runtime's `Jido.Plugin.state/2` | Read committed Plugin state from the live owner. Direct Agent state still contains the portable owned key. |
| `strategy/0`, `strategy_opts/0`, `strategy_snapshot/1` | No direct functions | Port execution to Actions or Flows and read live Turn state through the Server. |
| `signal_routes/0..1` | `routes/0`, `route_action/1` | An inline route can expose its generated Action module when needed for tests or codecs. |
| `new/1` | `new/1`, `new!/1` | The non-raising form now returns a tagged result. |
| `cmd/2..3` with an Action, Instruction, or list | `cmd/2..3` with one Signal | One Signal selects one executable. Put an Action sequence in one Flow. |
| `set/2`, `validate/1..2` | `Jido.Agent.set/2`, `validate/1`, `validate_definition/1`, or `validate_instance/1` | These functions are no longer generated on each Agent module. |
| No route interface helpers | Generated `name_signal`, `name_signal!`, and live `name` helpers from `define` | Treat `cmd/2` as the common boundary. Helpers package one route's input. |

### Other Agent modules

| V2 module | Status and V3 direction |
| --- | --- |
| `Jido.Agent.DefaultPlugins` | **Removed.** Declare every Plugin in the Agent definition. There are no implicit default Plugins. |
| `Jido.Agent.Schedules` | **Replaced** by `Jido.Plugin.Scheduler` and explicit Signal routes. |
| **Jido.Agent.State** | **Private in V3.** Use Agent constructors, `set/2`, and validation functions. Do not call state merge or schema-default helpers. |
| `Jido.Agent.StateOp` | **Removed.** Return the complete next state. |
| `Jido.Agent.StateOp.SetState` | **Removed.** Merge domain fields before the executable returns its complete state. |
| `Jido.Agent.StateOp.ReplaceState` | **Removed.** Return and validate the complete next state directly. |
| `Jido.Agent.StateOp.DeleteKeys` | **Removed.** Build the next state without the fields, subject to the declared schema. |
| `Jido.Agent.StateOp.SetPath` | **Removed.** Update the nested value in application code, then return the complete state. |
| `Jido.Agent.StateOp.DeletePath` | **Removed.** Update the nested value in application code, then return the complete state. |
| `Jido.Agent.StateOps` | **Removed.** There is no operation interpreter in the V3 Agent contract. |
| `Jido.Agent.Strategy` | **Removed.** Split domain execution, live admission, Plugin state, and post-commit work across their V3 owners. |
| `Jido.Agent.Strategy.Direct` | **Removed.** Signal routing and `Jido.Exec` supply the standard execution path. |
| `Jido.Agent.Strategy.FSM` | **Removed.** Keep state-machine data in the Agent schema and make transitions explicit Actions or Flows. |
| `Jido.Agent.Strategy.FSM.Machine` | **Removed.** Use an application state-machine value if the domain needs one. |
| `Jido.Agent.Strategy.InstructionTracking` | **Removed.** Use Turn outcomes for runtime status and application state or audit records for domain history. |
| `Jido.Agent.Strategy.Snapshot` | **Removed.** Use `Jido.AgentServer.status/2` or `snapshot/2`. Their result is not a V2 Strategy snapshot. |
| `Jido.Agent.Strategy.State` | **Removed.** Do not copy `__strategy__` state into V3. |
| `Jido.Agent.WorkerPool` | **Removed.** Use owned child Agents and an application capacity policy. |

### New V3 Agent contracts

| V3 module | Purpose | Migration use |
| --- | --- | --- |
| `Jido.Agent.Builder` | Builds definitions and instances in ordered programmatic steps. | Use it when the definition comes from application data rather than one module. |
| `Jido.Agent.Codec` | Encodes and decodes versioned authoring documents. | Use it for trusted Agent definition transport, not for Agent checkpoints. |
| `Jido.Agent.Codec.Registry` | Maps stable trusted IDs to modules, schemas, values, and executables. | Use explicit allowlists where V2 used Discovery or dynamic module names. |
| `Jido.Agent.Command` | Carries the Agent, Signal, and caller context through Plugin preparation. | Use it in `prepare/2` and `admit/3`. Do not store it as Agent state. |
| `Jido.Agent.Extension` | Lowers extra declarative Agent DSL entities into Core configuration. | Use it for static authoring extensions. It does not add a runtime. |
| `Jido.Agent.StateBudget` | Applies an optional byte limit to complete Agent state. | Set and test `max_state_size` when state growth needs a hard limit. |
| `Jido.Agent.Turn` | Declares one selected executable and its input. | Most applications observe it through the Server, not by constructing it. |
| `Jido.Agent.Turn.Outcome` | Gives one stable terminal Turn result. | Use it in error policy and observation code. It is not domain history. |

## Map the actor runtime

### `Jido.AgentServer`

Status: **Same name, new contract**.

The V2 Server exposes queue, completion, Strategy, lifecycle, and internal state
ideas. The V3 Server owns one serial Turn at a time. It validates and commits
the complete candidate state, then performs Directives in list order.

| V2 API | V3 API | Change |
| --- | --- | --- |
| `start/1`, `start_link/1`, `child_spec/1` | Same names | Startup accepts a V3 Agent module, definition, or instance. Prefer `Jido.start_agent/1..3` for instance supervision. |
| `call/3`, `cast/2` | Same names | The input must be a Signal. A successful call returns the committed Agent. |
| `state/1` | `agent/2`, `status/2`, `snapshot/2`, `children/2`, `plugin_state/3` | Select the smallest public view. Do not inspect the private state machine. |
| `await_completion/2`, `stream_status/2` | `call/3`, `send_request/3`, `receive_response/2` | V3 has no Strategy completion stream. |
| No startup readiness call | `await_ready/2` | This waits for declared Plugin runtime children. It does not wait for domain completion. |
| `attach/2`, `detach/2`, `touch/1` | Same operations with explicit timeout forms | The default idle timeout is still `:infinity`. |
| `adopt_child/4`, `stop_child/3` | Same names | The child identity and remote ownership contract changed. Test orphan and lost-reply cases. |
| No `children/2` view | `children/2` | Read the public child view instead of the private map. |
| `set_debug/2`, `recent_events/2` | `set_debug/3`, `recent_events/3` with default arguments | Event names and payloads changed around V3 Turns. |
| `whereis/2..3`, `via_tuple/2..3` | `whereis/3`, `via_tuple/3` | V3 takes an Agent Registry, not a Jido instance. Prefer `Jido.whereis_agent/1..3` for normal lookup. |
| Cancellation through `Jido.Await` | `cancel/2`, `cancel_turn/3` | A caller timeout does not cancel active execution. |
| No direct hibernate call | `hibernate/2` | The Server persists, then stops after the idle contract permits it. |

### Other Agent Server modules

| V2 module | Status and V3 direction |
| --- | --- |
| `Jido.AgentServer.ChildInfo` | **Same name, private data.** V3 adds activation, creation, lifecycle, and child-kind fields. Use `children/2`; do not convert stored structs. |
| `Jido.AgentServer.ParentRef` | **Same name, private data.** V3 adds a monitor, creation cause, and remote spawn reference. Use attach, detach, adopt, and parent-binding APIs. |
| **Jido.AgentServer.Options** | **Private in V3.** Use documented startup options. `storage` becomes `persistence`; restore and Turn limits are new; native schedules and custom directive handlers are rejected. |
| **Jido.AgentServer.State** | **Private in V3.** Use the public query functions. The V2 struct is not a migration format. |
| `Jido.AgentServer.Status` | **Removed.** `status/2` and `Jido.Agent.Turn.Outcome` cover separate live and terminal views. |
| `Jido.AgentServer.State.Lifecycle` | **Removed.** Runtime lifecycle state is private. |
| `Jido.AgentServer.Lifecycle` | **Removed.** Core does not expose the V2 lifecycle behavior. |
| `Jido.AgentServer.Lifecycle.Keyed` | **Removed.** Use the Jido instance registry and persistence APIs. |
| `Jido.AgentServer.Lifecycle.Noop` | **Removed.** Start an unmanaged Server directly, or use a Jido instance for managed ownership. |
| `Jido.AgentServer.DirectiveExec` | **Replaced** by typed Plugin Directives and the `c:Jido.Plugin.dispatch/4` callback. |
| `Jido.AgentServer.SignalRouter` | **Replaced** by Agent definition routes and the Jido Signal Router contract. |
| **Jido.AgentServer.Signal.ChildStarted** | **Private in V3.** Route the documented event type if the application needs it. Do not call its generated constructor as a Core API. |
| **Jido.AgentServer.Signal.Orphaned** | **Private in V3.** Handle the routed event or read the public relationship state. |
| `Jido.AgentServer.Signal.SensorExit` | **Removed.** A V3 SensorManager runtime owns sensor failure and repair. |
| `Jido.AgentServer.DirectiveContext` | **New.** It gives built-in Directive execution a bounded public context. Custom Plugin Directives receive `Jido.Plugin.DirectiveContext`. |

## Map Directives

The common Directive names do not mean that old serialized structs are safe to
reuse. Rebuild Directives with V3 constructors and test their post-commit
failure behavior.

| V2 module or constructor | V3 direction |
| --- | --- |
| `Jido.Agent.Directive` | **Same name, new contract.** `validate/1` and `built_in?/1` are new. The built-in set is closed; custom types belong to a declared Plugin. |
| `Jido.Agent.Directive.Emit`, `emit/2` | **Retained.** Delivery happens after commit. Use the Jido Signal V3 dispatch format. |
| `Jido.Agent.Directive.Error`, `error/2` | **Retained.** Prefer `{:error, reason}` when the Turn must fail before commit. |
| `Jido.Agent.Directive.Spawn`, `spawn/2` | **Retained.** It starts a generic supervised process. It does not make it a child Agent. |
| `Jido.Agent.Directive.SpawnAgent`, `spawn_agent/3` | **Same name, new contract.** V3 supports explicit remote placement through `node:` and has new lost-reply behavior. |
| `Jido.Agent.Directive.AdoptChild`, `adopt_child/3` | **Retained with new ownership data.** Test local and remote adoption. |
| `Jido.Agent.Directive.StopChild`, `stop_child/2` | **Retained.** It identifies the child by relationship tag. |
| `Jido.Agent.Directive.Stop`, `stop/1` | **Retained.** The state commit happens before the Server stops. |
| `emit_to_parent/3` | `Jido.Agent.Directive.EmitToParent` and `emit_to_parent/1` | The runtime resolves the current logical parent. Do not read a parent from Agent state. |
| No child-specific emit struct | `Jido.Agent.Directive.EmitToChild` and `emit_to_child/2` | Address a tracked child by tag. |
| `Jido.Agent.Directive.Cron` | `Jido.Plugin.Scheduler.Cron` | Declare the Scheduler Plugin first. |
| `Jido.Agent.Directive.CronCancel` | `Jido.Plugin.Scheduler.Cancel` | Cancellation updates Scheduler Plugin state. |
| `Jido.Agent.Directive.Schedule` | `Jido.Plugin.Scheduler.Schedule` | The scheduled payload is a Signal. |
| `Jido.Agent.Directive.RunInstruction` | A routed Action or Flow | There is no post-commit Instruction execution Directive. Send a later Signal when work must be a later Turn. |
| `Jido.Agent.Directive.StartSensor` | `Jido.Plugin.SensorManager.Start` | Port the old Sensor module to the V3 child contract. |
| `Jido.Agent.Directive.StopSensor` | `Jido.Plugin.SensorManager.Stop` | The SensorManager owns desired sensor state and repair. |

V2 exposes `schema/0` on each built-in Directive struct. V3 keeps those schemas
private. Use the constructor functions and `Jido.Agent.Directive.validate/1`.

## Replace V2 built-in Actions

V3 Core removes all V2 modules under `Jido.Actions`. Most of these modules are
small examples of a domain decision plus a Directive. Write an application
Action or an inline route Action that returns the complete next state and the
required V3 Directive.

| V2 module | V3 direction |
| --- | --- |
| `Jido.Actions.Control` | **Removed container module.** Declare application routes. |
| `Jido.Actions.Control.Cancel` | **Removed.** Decide whether cancellation is a live Turn cancellation or a domain state transition. Use `AgentServer.cancel/2` for the first case. |
| `Jido.Actions.Control.Noop` | **Removed.** Use a small application Action that returns `context.agent_state`. |
| `Jido.Actions.Control.Forward` | **Removed.** Return `emit/2`, `emit_to_child/2`, `emit_to_parent/1`, or `emit_to_pid/3` from an application Action. |
| `Jido.Actions.Control.Broadcast` | **Removed.** Return `Jido.Agent.Directive.emit/2` with a supported Jido Signal dispatch target from an application Action. |
| `Jido.Actions.Control.Reply` | **Removed.** Put the reply target in explicit input or caller context and emit a response Signal. |
| `Jido.Actions.Lifecycle` | **Removed container module.** Use runtime Directives from application Actions. |
| `Jido.Actions.Lifecycle.NotifyParent` | Use `Jido.Agent.Directive.emit_to_parent/1`. |
| `Jido.Actions.Lifecycle.NotifyPid` | Use `Jido.Agent.Directive.emit_to_pid/3`. |
| `Jido.Actions.Lifecycle.SpawnChild` | Use `Jido.Agent.Directive.spawn_agent/3`. |
| `Jido.Actions.Lifecycle.StopChild` | Use `Jido.Agent.Directive.stop_child/2`. |
| `Jido.Actions.Lifecycle.StopSelf` | Use `Jido.Agent.Directive.stop/1`. |
| `Jido.Actions.Scheduling` | **Removed container module.** Declare `Jido.Plugin.Scheduler`. |
| `Jido.Actions.Scheduling.ScheduleSignal` | Return `Jido.Plugin.Scheduler.schedule/2` from an application Action. |
| `Jido.Actions.Scheduling.ScheduleTimeout` | Schedule an explicit timeout Signal. Keep timeout identity in domain or Plugin state when it matters. |
| `Jido.Actions.Scheduling.ScheduleCron` | Return `Jido.Plugin.Scheduler.cron/4`. |
| `Jido.Actions.Scheduling.CancelCron` | Return `Jido.Plugin.Scheduler.cancel/1`. |
| `Jido.Actions.Status` | **Removed container module.** V3 does not reserve a domain status convention. |
| `Jido.Actions.Status.SetStatus` | Write an application Action against a declared status field. |
| `Jido.Actions.Status.MarkCompleted` | Write an application Action. A domain completion flag is separate from a Turn outcome. |
| `Jido.Actions.Status.MarkFailed` | Write an application Action, or return an error when state must not commit. |
| `Jido.Actions.Status.MarkWorking` | Write an application Action if this is domain state. Do not use it as a substitute for live Turn status. |
| `Jido.Actions.Status.MarkIdle` | Write an application Action if this is domain state. Actor idle state comes from `AgentServer.status/2`. |

## Map Plugins

### `Jido.Plugin`

Status: **Same name, new contract**.

`use Jido.Plugin` takes no options in V3. The Agent definition supplies each
Plugin's options. A Plugin can own one portable state key, one permanent runtime
root, and a set of typed Directive modules.

V2 also generates metadata and configuration functions such as `name/0`,
`description/0`, `category/0`, `tags/0`, `vsn/0`, `otp_app/0`, `state_key/0`,
`schema/0`, `config_schema/0`, `actions/0`, `capabilities/0`, `requires/0`,
`signal_patterns/0`, `signal_routes/0`, `subscriptions/0`, `schedules/0`,
`singleton?/0`, `manifest/0`, and `plugin_spec/1`. V3 does not generate this
catalog surface. Put options in the Agent Plugin declaration. Keep descriptive
metadata and capability discovery in the application when the application
needs them.

| V2 callback | V3 callback or owner |
| --- | --- |
| `plugin_spec/1` | Agent Plugin declaration plus optional `state_spec/1`, `directives/1`, and `child_spec/1` |
| `mount/2` | Static defaults in `state_spec/1`; live setup in `child_spec/1` |
| `handle_signal/2` | `prepare/2`, `admit/3`, or explicit Agent routing |
| `prepare_signal/2` | `prepare/2` for pure changes; `admit/3` for live checks |
| `prepare_action/3` | `prepare/2` or `admit/3` against `Jido.Agent.Command` |
| `prepare_emit/2` | `prepare_dispatch/4` with `Jido.Plugin.SignalContext` |
| `transform_result/3` | Domain change in the Action or Flow; owned Plugin state change in `update_state/3` |
| `subscriptions/2` | `Jido.Plugin.Bus` or `Jido.Plugin.SensorManager` |
| `signal_routes/1` | Agent routes |
| `on_checkpoint/2`, `on_restore/2` | Portable Plugin state in the Agent checkpoint; runtime reconstruction in `child_spec/1` and `await_ready/2` |
| `child_spec/1` with V2 config | `child_spec/1` with `Jido.Plugin.Init` |
| Custom `DirectiveExec` | `directives/1`, `validate_directive/2`, and `dispatch/4` |

### V2 Plugin support modules

| V2 module | Status and V3 direction |
| --- | --- |
| `Jido.Plugin.Config` | **Removed.** Validate Plugin options in callbacks or in an application constructor. |
| `Jido.Plugin.Instance` | **Removed.** V3 canonicalizes one declaration for each Plugin module. Aliased duplicate Plugin instances are not supported. |
| `Jido.Plugin.Manifest` | **Removed.** Keep descriptive capability metadata in the application when it is needed. |
| `Jido.Plugin.Requirements` | **Removed.** Validate applications, configuration, and dependent Plugins at application startup or definition construction. |
| `Jido.Plugin.Routes` | **Removed.** Put routes in the Agent definition. |
| `Jido.Plugin.Schedules` | **Replaced** by `Jido.Plugin.Scheduler`. |
| **Jido.Plugin.Spec** | **Private in V3.** Do not construct or store it. |

### New V3 Plugin modules

| V3 module | Purpose |
| --- | --- |
| `Jido.Plugin.Init` | Gives a Plugin runtime its owner, module, and declared options. It is not a state snapshot. |
| `Jido.Plugin.SignalContext` | Gives outbound Signal preparation a bounded context. |
| `Jido.Plugin.DirectiveContext` | Gives post-commit Plugin dispatch its Agent and Plugin state view. |
| `Jido.Plugin.Codec` | Encodes Plugin declarations through the trusted Agent codec Registry. |
| `Jido.Plugin.Audit` | Commits selected domain audit records in Plugin-owned state. |
| `Jido.Plugin.Audit.Record` | Holds one portable audit record. |
| `Jido.Plugin.Dispatch` | Owns explicit post-commit Signal delivery. |
| `Jido.Plugin.Dispatch.Send` | Describes one Plugin-owned Signal delivery request. |
| `Jido.Plugin.Bus` | Owns a Signal Bus subscription for one Agent. |
| `Jido.Plugin.Bus.Client` | Gives the Agent Plugin a Bus client runtime. |
| `Jido.Plugin.Bus.Manager` | Owns shared Bus processes under the Jido instance. |
| `Jido.Plugin.Heartbeat` | Sends periodic input Signals to an Agent. |
| `Jido.Plugin.Scheduler` | Owns scheduled and recurring Signal delivery state. |
| `Jido.Plugin.Scheduler.Schedule` | Describes one delayed Signal. |
| `Jido.Plugin.Scheduler.Cron` | Describes one recurring Signal schedule. |
| `Jido.Plugin.Scheduler.Cancel` | Removes one recurring schedule. |
| `Jido.Plugin.Scheduler.Enqueue` | Records one due occurrence through an Agent Turn before later business work. |
| `Jido.Plugin.Scheduler.Occurrence` | Carries stable occurrence identity for delivery and recovery. |
| `Jido.Plugin.Scheduler.Acknowledge` | Commits occurrence acknowledgement with domain state. |
| `Jido.Plugin.SensorManager` | Keeps desired resource processes aligned with Plugin state. |
| `Jido.Plugin.SensorManager.Init` | Gives one sensor process its Agent owner and configuration. |
| `Jido.Plugin.SensorManager.Start` | Adds or replaces one desired sensor process. |
| `Jido.Plugin.SensorManager.Stop` | Removes one desired sensor process. |

## Replace Pods and worker pools

V2 Pods own a mutable live graph. V3 Topology declares a static system before
process startup. A controller can repair that target. It cannot change the
definition while it runs.

| V2 module | V3 direction |
| --- | --- |
| `Jido.Pod` | `Jido.Topology` plus `Jido.Topology.Controller` for static startup and repair. Use an application controller for dynamic membership. |
| `Jido.Pod.Plugin` | Topology ownership declarations or a custom V3 Plugin. |
| `Jido.Pod.Topology` | `Jido.Topology` for declarations and `Jido.Topology.Plan` for the expanded local plan. |
| `Jido.Pod.Topology.Node` | An Agent or group declaration in `Jido.Topology`. |
| `Jido.Pod.Topology.Link` | An ownership, subscription, import, or export declaration. Select the exact relationship. |
| `Jido.Pod.Mutation` | **Removed.** V3 has no live definition update contract. |
| `Jido.Pod.Mutation.AddNode` | **Removed.** Put fixed members in the definition. Let an application controller own dynamic members. |
| `Jido.Pod.Mutation.RemoveNode` | **Removed.** Stop application-owned dynamic members outside the static topology target. |
| `Jido.Pod.Mutation.Plan` | **Removed.** Do not translate a V2 mutation plan into a V3 static plan. |
| `Jido.Pod.Mutation.Planner` | **Removed.** Application code owns live change planning. |
| `Jido.Pod.Mutation.Report` | **Removed.** Define an application result for dynamic changes. |
| `Jido.Agent.WorkerPool` | **Removed.** Use a bounded set of owned child Agents or an application-managed pool. |

### New V3 Topology modules

| V3 module | Purpose |
| --- | --- |
| `Jido.Topology` | Declares Agents, groups, Buses, ownership, connections, imports, exports, and startup policy. |
| `Jido.Topology.Builder` | Builds the same declaration through programmatic steps. |
| `Jido.Topology.Codec` | Encodes and decodes trusted topology authoring documents. |
| `Jido.Topology.Instance` | Holds validated topology input and one local plan. |
| `Jido.Topology.Plan` | Holds stable IDs, dependency layers, and expanded local resources. |
| `Jido.Topology.Ref` | Refers to one exported value from an included topology. |
| `Jido.Topology.Reference` | Refers to topology input or one keyed group member. |
| `Jido.Topology.Controller` | Starts and repairs one static topology on one local Jido instance. |

## Replace Await, Scheduler, and Sensor modules

| V2 module | V3 direction |
| --- | --- |
| `Jido.Await` | **Removed.** Replace `alive?/1` with `AgentServer.alive?/1`; replace `completion/3` with a call or request; coordinate `all/3` and `any/3` in the application; use `children/2` for child views; and use `cancel/2` or `cancel_turn/3` for cancellation. Do not map `await_ready/2` to V2 completion. |
| `Jido.Scheduler` | **Replaced** by `Jido.Plugin.Scheduler`. Replace `run_every/3..5`, cron-spec helpers, and `cancel/1` with Scheduler Plugin Directives and Agent routes. Scheduler state belongs to the Agent Plugin state. |
| `Jido.Sensor` | **Removed behavior.** Its `init/2`, `handle_event/2`, and `terminate/2` callbacks do not have a callback-for-callback port. Port the resource to a standard OTP child that accepts `Jido.Plugin.SensorManager.Init`. |
| `Jido.Sensor.Runtime` | **Replaced** by the SensorManager-owned child and its application module. |
| `Jido.Sensor.Spec` | **Replaced** by a SensorManager tag, module, and portable config map. |
| `Jido.Sensors.Heartbeat` | **Replaced** by `Jido.Plugin.Heartbeat`. |
| `Jido.Sensors.Bus` | The V2 docs group names this module, but the V2 baseline does not compile it. Use `Jido.Plugin.Bus` for Agent Bus input. |

## Map persistence, Threads, Memory, and identity

### Persistence

| V2 module | V3 direction |
| --- | --- |
| `Jido.Storage` | `Jido.Persistence` for Agent checkpoints. Use an application store for other data. |
| `Jido.Storage.ETS` | `Jido.Persistence.ETS`, with a new binary adapter and compare-and-swap contract. |
| `Jido.Storage.File` | `Jido.Persistence.File`, with new record keys, bytes, ownership, and conflict behavior. |
| `Jido.Storage.Redis` | `Jido.Persistence.Redis`, with new record keys and atomic compare-and-swap behavior. |
| `Jido.Persist` | `Jido.Persistence` plus `Jido.hibernate/1..3` and `Jido.thaw/2..4`. |
| `Jido.Agent.InstanceManager` | `Jido.start_agent/1..3`, registry lookup, persistence, hibernate, and thaw. There is no public manager process API. |

The V2 `Jido.Storage` callbacks mix checkpoint and Thread operations. The V3
`Jido.Persistence.Adapter` stores binary keys and values through `get/2`,
`put/3`, `compare_and_swap/4`, and `delete/2`. A get followed by a put is not a
valid compare-and-swap implementation. Decode V2 data with V2 code, transform
it, and save a new V3 record. Do not point both versions at the same keys.

V3 adds these modules:

| V3 module | Purpose |
| --- | --- |
| `Jido.Persistence` | Owns Agent record keys, encoding, revision checks, restore, and adapter fault containment. |
| `Jido.Persistence.Adapter` | Defines the minimal byte-store contract. |
| `Jido.Persistence.ETS` | Supplies local in-memory Agent persistence. |
| `Jido.Persistence.File` | Supplies file-backed Agent persistence with one owner per directory. |
| `Jido.Persistence.Redis` | Supplies Redis-backed Agent persistence. |

### Threads

| V2 module | Status and V3 direction |
| --- | --- |
| `Jido.Thread` | **Removed.** Define the required history value in the application schema. |
| `Jido.Thread.Entry` | **Removed.** Define application entry types and validation rules. |
| `Jido.Thread.EntryNormalizer` | **Removed.** Normalize history at the application boundary. |
| `Jido.Thread.Agent` | **Removed.** Put history in the declared Agent data schema and return its next value from an Action. |
| `Jido.Thread.Plugin` | **Removed.** V3 does not capture message history automatically. |
| `Jido.Thread.Store` | **Removed.** Persist Threads in an application-owned store. |
| `Jido.Thread.Store.Adapters.InMemory` | **Removed.** Use an application test store. |
| `Jido.Thread.Store.Adapters.JournalBacked` | **Removed.** Convert old journal data while a V2 reader is available. |

### Memory and identity

| V2 module | V3 direction |
| --- | --- |
| `Jido.Memory` | **Removed.** Define the needed memory value in application state or an external store. |
| `Jido.Memory.Space` | **Removed.** Define explicit list, map, retention, and compaction rules in the application. |
| `Jido.Memory.Agent` | **Removed.** Update memory through routed Actions that return complete state. |
| `Jido.Memory.Plugin` | **Removed.** Write a V3 Plugin only when memory needs owned state or a live resource. |
| `Jido.Agent.Identity` | **Removed.** Define identity and revision data in the application domain. |
| `Jido.Agent.Identity.Agent` | **Removed.** Access identity through application functions. |
| `Jido.Agent.Identity.Plugin` | **Removed.** Use a custom V3 Plugin only when identity needs a runtime capability. |
| `Jido.Agent.Identity.Profile` | **Removed.** Keep profile policy and evolution in the application. |
| `Jido.Agent.Identity.Actions.Evolve` | **Removed.** Write an application Action with explicit migration rules. |

## Map observation, errors, and utilities

### Observation

| V2 module | Status and V3 direction |
| --- | --- |
| `Jido.Observe` | **Retained call surface.** Event names and metadata changed for V3 Turn stages. Port every attached handler. |
| `Jido.Observe.Config` | **Retained call surface.** Review precedence and remove settings for deleted runtime features. |
| `Jido.Observe.Log` | **Retained.** Test redaction and log levels with V3 Signal and Turn data. |
| `Jido.Observe.Tracer` | **Retained behavior.** Test callback failure policy and V3 span metadata. |
| `Jido.Observe.NoopTracer` | **Retained.** |
| `Jido.Observe.SpanCtx` | **Retained.** Do not store live tracer values in Agent state. |
| `Jido.Observe.EventContract` | **Removed.** Use the documented V3 event contract and tests. |
| `Jido.Telemetry` | **Same name, changed events.** `span_agent_cmd/3` and `span_strategy/4` are removed. Use the V3 lifecycle, Turn, commit, and Directive events. |
| `Jido.Telemetry.Config` | **Removed.** Use application configuration and `Jido.Observe.Config`. |
| `Jido.Telemetry.Formatter` | **Retained call surface.** Its accepted V3 data shapes changed. |
| `Jido.Tracing.Context` | **Retained call surface.** Also follow the Jido Signal V3 trace migration. |
| `Jido.Tracing.Trace` | **Retained call surface.** It now delegates more Signal trace work to the Signal contract. |
| `Jido.Debug` | **Retained call surface.** Agent event contents and Server queries changed. |

### Errors and utility modules

| V2 module | Status and V3 direction |
| --- | --- |
| `Jido.Error` | **Retained except for NimbleOptions formatters.** `format_nimble_config_error/3` and `format_nimble_validation_error/3` are removed. |
| `Jido.Error.CompensationError` | **Retained type.** Jido Action V3 removes built-in retry and compensation policy. Do not assume the old execution path creates it. |
| `Jido.Error.ExecutionError` | **Retained type.** Test error details at Action, Flow, and Server boundaries. |
| `Jido.Error.InternalError` | **Retained type.** |
| `Jido.Error.RoutingError` | **Retained type with a stronger V3 role.** Missing, invalid, and multiple Agent route matches return it. |
| `Jido.Error.TimeoutError` | **Retained type.** Separate caller timeout from active Turn cancellation. |
| `Jido.Error.ValidationError` | **Retained type.** Zoi now supplies schema issues. |
| `Jido.Config.Defaults` | **Same name, smaller contract.** Await, Server timeout, InstanceManager, and WorkerPool default functions are removed. |
| `Jido.RuntimeStore` | **Retained call surface.** It is instance-local coordination state, not durable application storage. Do not migrate stored values by copying its internal keys. |
| `Jido.Discovery` | **Removed.** Its catalog, list, slug lookup, refresh, timestamp, and asynchronous initialization functions have no Core V3 catalog. Use explicit modules and a trusted `Jido.Agent.Codec.Registry`. |
| `Jido.Util` | **Retained call surface for internal support.** Prefer the domain modules that own validation, IDs, lookup, and executable resolution. |

## Remove installer and generator calls

The following V2 Mix tasks are removed:

- `Mix.Tasks.Jido.Install`
- `Mix.Tasks.Jido.Gen.Agent`
- `Mix.Tasks.Jido.Gen.Plugin`
- `Mix.Tasks.Jido.Gen.Sensor`

Add the Jido instance to the application supervision tree. Create Agent,
Plugin, Action, and sensor modules from the current guides. Do not copy a V2
generated module and then change only the dependency version.

## Treat old internals as application ports

The V2 source also contains hidden implementation modules. These include
`Jido.Agent.InstanceManager.Cleanup`, `Jido.Agent.Schema`,
`Jido.AgentServer.CronRuntimeSpec`, `Jido.AgentServer.ErrorPolicy`,
`Jido.AgentServer.SensorLifecycle`, `Jido.AgentServer.Signal.CronTick`,
`Jido.AgentServer.Signal.Scheduled`, `Jido.AgentServer.StopChildRuntime`,
`Jido.Igniter.Helpers`, `Jido.Igniter.Templates`, `Jido.Pod.Actions.Mutate`,
`Jido.Pod.Definition`, `Jido.Pod.Directive.ApplyMutation`, `Jido.Pod.Mutable`,
`Jido.Pod.Runtime`, `Jido.Pod.TopologyState`, `Jido.Scheduler.Job`, and
`Jido.Storage.ETS.Owner`.

There is no supported one-to-one migration for these modules. If application
code calls one, first record the behavior that the application needs. Then
port that behavior through a public V3 contract or make it application-owned.
Do not copy a V2 internal struct or callback into V3.

**Jido.Application**, **Jido.ID**, and **Jido.Util.DeepMerge** remain private. Their
continued names do not make them public migration contracts.

## Build the migration documentation from this map

The next migration examples should follow this order:

1. Convert one Agent declaration and constructor.
2. Convert direct Action commands to Signal routes and complete-state results.
3. Move a live call to the V3 Actor runtime.
4. Port one simple Plugin, then one Plugin with owned state and a runtime.
5. Port each Directive family and test commit ordering.
6. Replace Strategy, Await, Sensor, Scheduler, WorkerPool, and Pod use.
7. Convert real stored data with old and new fixtures.
8. Port observation handlers and failure-path assertions.
9. Record every removed module as replaced, application-owned, or intentionally deleted.

For each example, show the V2 code, the V3 code, the changed guarantee, and one
test that proves the application still has the required behavior. Do not call a
migration complete because the new code compiles.
