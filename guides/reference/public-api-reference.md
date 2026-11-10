# Public API Guide

This guide lists the public functions of the Jido modules you call most, grouped by task. Use it to find a function, then follow its link for the full document. It is a map of the API, not a replacement for the generated module pages.

A module is public when it has a module document, and a function is public when it has a function document. `@doc false` functions are private even when they are exported. The [Module and Namespace Map](module-and-namespace-map.md) lists every public module, including the many Action modules inside `Jido.AI.Reasoning`.

Each table is generated from the function documents. The arity shown is the highest one. A function with default arguments also has lower arities, so `Jido.AgentServer.call/3` can also be called with two arguments.

## Functions that `use` generates

`use` adds functions to your own module. These do not appear in the module tables below.

| You write | Your module gets |
| --- | --- |
| `use Jido, otp_app: :my_app` | `child_spec/1`, `start_link/1`, and `config/1` |
| `use Jido.Agent` | `instantiate/1`, `instantiate!/1`, `definition/0`, `schema/0`, `vsn/0`, `cmd/3`, and a `<as>_signal/2` and `<as>_signal!/2` pair for each named route |
| `use Jido.Action` | `run/2` (yours), `name/0`, `description/0`, `schema/0`, `output_schema/0`, `validate_params/1`, `validate_output/1`, `authoring_contract/0` |
| `use Jido.Flow` | `flow/0`, `run/2`, `name/0`, `description/0`, `schema/0`, `output_schema/0`, `validate_params/1`, `validate_output/1`, `authoring_contract/0` |
| `use Jido.Signal` | `type/0`, `default_source/0`, `datacontenttype/0`, `dataschema/0`, `schema/0`, `validate_data/1`, `new/2`, `new!/2` |

```elixir
defmodule ApiGuide.Reserve do
  use Jido.Action,
    name: "reserve_stock",
    schema: Jido.Joi.object(%{sku: Jido.Joi.string()})

  @impl true
  def run(%{sku: sku}, _context), do: {:ok, %{reserved: sku}}
end

defmodule ApiGuide.OrderFlow do
  use Jido.Flow,
    name: "order_flow",
    schema: Jido.Joi.object(%{sku: Jido.Joi.string()})

  flow do
    step "reserve", action: ApiGuide.Reserve, params: %{sku: input(:sku)}
    output result("reserve")
  end
end

defmodule ApiGuide.Order do
  use Jido.Agent, name: "api_guide_order"

  state do
    schema Jido.Joi.object(%{status: Jido.Joi.string() |> Jido.Joi.default("new")})
  end

  routes do
    signal_source "/orders"

    route "order.place", as: :place do
      action %{}, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | status: "placed"}}
      end
    end
  end
end

defmodule ApiGuide.OrderPlaced do
  use Jido.Signal,
    type: "order.placed",
    default_source: "/orders",
    schema: Jido.Joi.object(%{id: Jido.Joi.string()})
end

for {module, functions} <- [
      {ApiGuide.Reserve, [name: 0, run: 2, validate_params: 1, validate_output: 1, authoring_contract: 0]},
      {ApiGuide.OrderFlow, [flow: 0, run: 2, name: 0, validate_params: 1, authoring_contract: 0]},
      {ApiGuide.Order, [instantiate: 1, instantiate!: 1, definition: 0, schema: 0, vsn: 0, cmd: 3, place_signal: 2, place_signal!: 2]},
      {ApiGuide.OrderPlaced, [type: 0, default_source: 0, schema: 0, validate_data: 1, new: 2, new!: 2]}
    ],
    {name, arity} <- functions do
  true = function_exported?(module, name, arity)
end

{:ok, %{reserved: "sku-1"}} = Jido.Exec.run(ApiGuide.OrderFlow, %{sku: "sku-1"})
```

A `use Jido` instance has no generated runtime functions. Pass the instance to `Jido` functions, as in `Jido.start_agent(MyApp.Jido, MyApp.Order)`.

## Behaviours

Implement these to extend Jido. An optional callback can be left out.

| Behaviour | Required callbacks | Optional callbacks | Guide |
| --- | --- | --- | --- |
| `Jido.Action` | `c:Jido.Action.run/2` | `c:Jido.Action.on_before_validate_params/1` | [Actions](../actions/actions.md) |
| `Jido.Agent` | None | `c:Jido.Agent.initialize/2`, `c:Jido.Agent.checkpoint/2`, `c:Jido.Agent.restore/2` | [Agent Callbacks](../agents/agent-callbacks.md) |
| `Jido.Plugin` | None | `c:Jido.Plugin.state_spec/1`, `c:Jido.Plugin.validate_options/1`, `c:Jido.Plugin.directives/1`, `c:Jido.Plugin.select_route/2`, `c:Jido.Plugin.prepare/2`, `c:Jido.Plugin.reduce/2`, `c:Jido.Plugin.admit/3`, `c:Jido.Plugin.prepare_outbound/4`, `c:Jido.Plugin.dispatch/4`, `c:Jido.Plugin.after_commit/3`, `c:Jido.Plugin.child_spec/1`, `c:Jido.Plugin.await_ready/2`, `c:Jido.Plugin.quiesce/2`, `c:Jido.Plugin.resume/2`, `c:Jido.Plugin.dump/3`, `c:Jido.Plugin.load/3` | [Plugin Design](../plugins/plugin-design.md) |
| `Jido.Persistence.Store` | `c:Jido.Persistence.Store.get/2`, `c:Jido.Persistence.Store.compare_and_swap/4` | `c:Jido.Persistence.Store.validate_options/1`, `c:Jido.Persistence.Store.put/3`, `c:Jido.Persistence.Store.delete/2` | [Custom Adapters](../storage/custom-persistence-adapter.md) |
| `Jido.Signal.Dispatch.Adapter` | `c:Jido.Signal.Dispatch.Adapter.options_schema/0`, `c:Jido.Signal.Dispatch.Adapter.deliver/2` | None | [Signal Dispatch Adapters](../signals/dispatch-adapters.md) |
| `Jido.Signal.Bus.Store` | `c:Jido.Signal.Bus.Store.init/1`, `c:Jido.Signal.Bus.Store.append/2`, `c:Jido.Signal.Bus.Store.read/2`, `c:Jido.Signal.Bus.Store.latest_cursor/1`, `c:Jido.Signal.Bus.Store.put_subscription/2`, `c:Jido.Signal.Bus.Store.list_subscriptions/1`, `c:Jido.Signal.Bus.Store.delete_subscription/2` | None | [Durable Subscriptions](../signals/durable-subscriptions.md) |
| `Jido.Plugin.Scheduler.DeliveryAdapter` | `c:Jido.Plugin.Scheduler.DeliveryAdapter.schedule/3`, `c:Jido.Plugin.Scheduler.DeliveryAdapter.reconcile/2` | None | [Schedules](../built-in-plugins/scheduler.livemd) |
| `Jido.Codec.Contract` | `c:Jido.Codec.Contract.type/0`, `c:Jido.Codec.Contract.version/0`, `c:Jido.Codec.Contract.target/0`, `c:Jido.Codec.Contract.decode/2` | `c:Jido.Codec.Contract.encode/2` | [Jido.Codec Documents](../data/versioned-documents.md) |
| `Jido.AI.ToolSource` | `c:Jido.AI.ToolSource.list_tools/2`, `c:Jido.AI.ToolSource.run_tool/3` | None | [Tools and Toolsets](../ai/tools-skills-and-toolsets.livemd) |
| `Jido.AI.InferenceClient` | Each model operation, 22 callbacks. Start from `c:Jido.AI.InferenceClient.generate_text/3`. | None | [Inference Clients](../ai/inference-clients.md) |

`use Jido.Action` generates `validate_params/1` and `validate_output/1`, so `run/2` is the only one you write. A `Jido.Flow.Extension` provides Flow DSL macros. See [Flow Extensions](../flows/flow-modules.md).

## Schemas

`Jido.Joi` has 93 public functions, one for each schema type and refinement, so this guide does not list them. See [Jido.Joi Validation](../data/joi-validation.md) and the `Jido.Joi` module page.

## Instances and stable Agent Refs

Guides: [Instances and Tenants](../operations/configuration-and-tenant-isolation.md).

### `Jido`

自動 (Jido) - A declarative actor and agent framework for Elixir, built for workflows and multi-agent systems.

| Function | Summary |
| --- | --- |
| `Jido.activate_agent/4` | Restores or creates one durable Agent with an explicit stable Agent Ref. |
| `Jido.agent/3` | Returns the committed Agent through a stable Agent Ref. |
| `Jido.agent_count/2` | Counts live Agents with options in the selected Jido instance. |
| `Jido.agent_ref/3` | Builds one stable Agent Ref in the selected instance namespace. |
| `Jido.attach/4` | Attaches an owner process through a stable Agent Ref. |
| `Jido.await_ready/3` | Waits for runtime readiness through a stable Agent Ref. |
| `Jido.call/4` | Sends one synchronous Signal through a stable Agent Ref. |
| `Jido.cancel/3` | Cancels current pre-commit work for one stable Agent Ref. |
| `Jido.cancel_turn/4` | Cancels one matching Turn for a stable Agent Ref. |
| `Jido.cast/3` | Sends one best-effort asynchronous Signal through a stable Agent Ref. |
| `Jido.children/3` | Returns child runtime status through a stable Agent Ref. |
| `Jido.delete_agent/4` | Writes a durable tombstone for one inactive stable Agent Ref. |
| `Jido.detach/4` | Detaches an owner process through a stable Agent Ref. |
| `Jido.hibernate/3` | Hibernates an Agent with options in the selected Jido instance. |
| `Jido.hibernate_ref/3` | Persists and stops the local Agent resolved by a stable Agent Ref. |
| `Jido.list_agents/2` | Lists Agents with options in the selected Jido instance. |
| `Jido.plugin_state/4` | Returns one Plugin-owned field from the complete Agent state through a stable Ref. |
| `Jido.resolve_agent/2` | Resolves the current local worker for one stable Agent Ref. |
| `Jido.start/1` | Start the default Jido instance for scripts and Livebook. |
| `Jido.start_agent/3` | Starts one Agent under the selected Jido instance supervisor. |
| `Jido.start_agent_ref/4` | Starts one Agent with an explicit stable Agent Ref. |
| `Jido.start_link/1` | Starts a Jido instance supervisor. |
| `Jido.status/3` | Returns Turn status through a stable Agent Ref. |
| `Jido.stop/1` | Stop a Jido instance. |
| `Jido.stop_agent/3` | Stops an Agent with options in the selected Jido instance. |
| `Jido.stop_agent_ref/4` | Stops the local Agent resolved by a stable Agent Ref. |
| `Jido.submit/4` | Submits one AgentServer turn through a stable Agent Ref. |
| `Jido.thaw/4` | Thaws an Agent with options in the selected Jido instance. |
| `Jido.touch/2` | Resets the idle timer through a stable Agent Ref. |
| `Jido.whereis_agent/3` | Looks up an Agent with options in the selected Jido instance. |

## Live Agents

Guides: [Start and Address Agents](../agent-servers/start-and-address-live-agents.livemd), [Call, Cast, and Await](../agent-servers/send-signals-to-live-agents.livemd).

### `Jido.AgentServer`

Runs one serialized Agent Turn at a time.

| Function | Summary |
| --- | --- |
| `Jido.AgentServer.abandon/1` | Discards a pending reply and releases its OTP request monitor. |
| `Jido.AgentServer.activation/1` | Returns the activation supervisor PID, or nil for a bare worker. |
| `Jido.AgentServer.adopt_child/4` | Attaches an independent orphan to a new logical parent in the same instance and partition. |
| `Jido.AgentServer.agent/2` | Returns the saved Agent instance. |
| `Jido.AgentServer.alive?/1` | Returns true for a live local AgentServer PID or OTP name. |
| `Jido.AgentServer.attach/3` | Attaches one owner. |
| `Jido.AgentServer.await/2` | Waits for a submitted turn and returns the same turn result as `call/3`. |
| `Jido.AgentServer.await_ready/2` | Waits for Plugin startup and readiness. |
| `Jido.AgentServer.call/3` | Runs one Signal. |
| `Jido.AgentServer.cancel/2` | Cancels the active turn and waits for owned work to stop. |
| `Jido.AgentServer.cancel_turn/3` | Cancels only the active turn with this ID. |
| `Jido.AgentServer.cast/3` | Sends one Signal without a reply, with optional `context:`. |
| `Jido.AgentServer.child_spec/1` | Returns a child specification for OTP supervision. |
| `Jido.AgentServer.children/2` | Returns live tagged children with separate worker and activation PIDs. |
| `Jido.AgentServer.deliver_wait/4` | Saves a Signal as input to an open durable Flow wait. |
| `Jido.AgentServer.detach/3` | Detaches one owner. |
| `Jido.AgentServer.hibernate/2` | Saves the settled Agent at its current revision, then stops the activation. |
| `Jido.AgentServer.history/1` | Returns terminal summaries in chronological order when debug is enabled. |
| `Jido.AgentServer.members/3` | Returns live topology members in slot order. |
| `Jido.AgentServer.plugin_state/3` | Returns one committed Plugin-owned state field. |
| `Jido.AgentServer.quiesce/2` | Closes admission and rejects queued turns with `:quiesced`. |
| `Jido.AgentServer.resume/2` | Opens admission after quiescence. |
| `Jido.AgentServer.snapshot/2` | Returns one committed Agent and revision from the same server event. |
| `Jido.AgentServer.spawn_child/4` | Starts a tagged local child Agent. |
| `Jido.AgentServer.start/1` | Starts a registered AgentServer under the selected Jido instance supervisor. |
| `Jido.AgentServer.start_link/1` | Starts a bare worker with one validated Agent instance and a running `runner:`. |
| `Jido.AgentServer.status/2` | Returns phase, identity, revision, queue counts, and a bounded active turn view. |
| `Jido.AgentServer.stop/3` | Stops the server and its active turn through OTP termination. |
| `Jido.AgentServer.stop_child/3` | Stops the complete tagged child activation and confirms its shutdown. |
| `Jido.AgentServer.submit/3` | Submits one turn with optional `context:` and `admission_timeout:` and returns a pending result handle. |
| `Jido.AgentServer.touch/1` | Restarts the idle budget. |
| `Jido.AgentServer.upgrade/3` | Runs a snapshot upgrade Action through the serial commit boundary. |
| `Jido.AgentServer.whereis/3` | Looks up an AgentServer in one instance and partition. |
| `Jido.AgentServer.worker/1` | Returns the live request worker for an activation root, or nil when unavailable. |

### `Jido.AgentServer.Directive`

Runtime requests.

| Function | Summary |
| --- | --- |
| `Jido.AgentServer.Directive.agent_start/3` | Builds a Directive that starts and tracks one local Agent. |
| `Jido.AgentServer.Directive.agent_stop/2` | Builds a Directive that stops and untracks one child Agent. |
| `Jido.AgentServer.Directive.error_report/2` | Builds a Directive that applies the AgentServer error policy after commit. |
| `Jido.AgentServer.Directive.process_start/1` | Builds a Directive that starts one independent OTP child under the Jido instance. |
| `Jido.AgentServer.Directive.signal_send/3` | Builds an Emit Directive that sends one Signal to a local process. |

### `Jido.AgentServer.Plugin`

Live Plugin state access and lifecycle policy for one AgentServer.

| Function | Summary |
| --- | --- |
| `Jido.AgentServer.Plugin.state/2` | Reads the current state owned by one live Plugin runtime. |

### `Jido.AgentServer.Command`

The live AgentServer admission envelope.

| Function | Summary |
| --- | --- |
| `Jido.AgentServer.Command.new/3` | Creates one validated AgentServer command. |
| `Jido.AgentServer.Command.validate/1` | Validates one AgentServer command. |

## Agent definitions and Turns

Guides: [Define an Agent](../agents/define-and-instantiate-an-agent.livemd), [State and Directives](../agents/agent-results-and-directives.md).

### `Jido.Agent`

Author Agent definitions as Maps or with the Spark DSL.

| Function | Summary |
| --- | --- |
| `Jido.Agent.build_signal/3` | Builds one Agent-owned Signal from an Action context without dispatching it. |
| `Jido.Agent.cmd/3` | Runs one complete Turn through `Jido.Exec.run/4` without an AgentServer. |
| `Jido.Agent.define/1` | Builds and validates a neutral Agent definition from a plain Map. |
| `Jido.Agent.define!/1` | Builds one neutral Agent definition or raises its validation error. |
| `Jido.Agent.definition/1` | Returns the neutral definition for an Agent value or compiled Agent module. |
| `Jido.Agent.definition?/1` | Checks definition shape only. |
| `Jido.Agent.instance?/1` | Checks instance shape only. |
| `Jido.Agent.instantiate/2` | Builds and validates one Agent instance from a definition or compiled Agent module. |
| `Jido.Agent.instantiate!/2` | Builds one Agent instance or raises its validation error. |
| `Jido.Agent.mutate/2` | Applies ordered data mutations and returns the candidate and its final Diff. |
| `Jido.Agent.schema/1` | Returns the state schema, including Plugin-owned fields. |
| `Jido.Agent.set/2` | Replaces supplied top-level domain fields and validates the complete next state. |
| `Jido.Agent.validate/1` | Validates a definition or instance, including schema, routes, and provider data. |

### `Jido.Agent.Directive`

Changes and runtime work returned by an Agent executable turn.

| Function | Summary |
| --- | --- |
| `Jido.Agent.Directive.agent_add/3` | Adds one named logical Agent member. |
| `Jido.Agent.Directive.agent_remove/1` | Removes one named logical Agent member. |
| `Jido.Agent.Directive.agent_replace/3` | Replaces one named logical Agent member. |
| `Jido.Agent.Directive.agent_send/2` | Creates a request to send one Signal to a tracked child Agent after commit. |
| `Jido.Agent.Directive.agent_update/2` | Updates selected fields of one named logical Agent member. |
| `Jido.Agent.Directive.connection_add/2` | Adds one logical output connection. |
| `Jido.Agent.Directive.connection_remove/2` | Removes one logical output connection. |
| `Jido.Agent.Directive.connection_replace/2` | Replaces one logical output connection. |
| `Jido.Agent.Directive.connection_update/2` | Updates the delivery fields of one logical output connection. |
| `Jido.Agent.Directive.emit/2` | Creates an emission request. |
| `Jido.Agent.Directive.parent_send/1` | Creates a request to send one Signal to the parent Agent after commit. |
| `Jido.Agent.Directive.plugin_add/3` | Adds one runtime Plugin declaration and initializes its owned state. |
| `Jido.Agent.Directive.plugin_configure/3` | Changes one runtime Plugin declaration with an optional state migration. |
| `Jido.Agent.Directive.plugin_remove/2` | Removes one runtime Plugin declaration with an explicit state policy. |
| `Jido.Agent.Directive.reply/1` | Creates one correlated response request. |
| `Jido.Agent.Directive.route_add/3` | Adds one Agent route. |
| `Jido.Agent.Directive.route_remove/1` | Removes one Agent route. |
| `Jido.Agent.Directive.route_replace/3` | Replaces one Agent route. |
| `Jido.Agent.Directive.route_update/2` | Updates selected fields of one Agent route. |
| `Jido.Agent.Directive.routes_reorder/1` | Sets the complete order of the current Agent routes. |
| `Jido.Agent.Directive.routes_set/1` | Replaces the complete Agent route list. |
| `Jido.Agent.Directive.server_stop/1` | Creates a terminal request to stop the AgentServer after commit. |
| `Jido.Agent.Directive.topology_set/1` | Replaces the complete topology data. |
| `Jido.Agent.Directive.validate/1` | Validates one built-in or custom Agent Directive. |

### `Jido.Agent.Turn`

A prepared executable turn for one Agent Signal.

| Function | Summary |
| --- | --- |
| `Jido.Agent.Turn.new/2` | Creates and validates one Turn. |
| `Jido.Agent.Turn.new/3` | Creates and validates one Turn for an unchanged source Signal. |
| `Jido.Agent.Turn.new!/2` | Creates one Turn or raises its validation error. |
| `Jido.Agent.Turn.new!/3` | Creates one Turn for an unchanged source Signal or raises its validation error. |
| `Jido.Agent.Turn.schema/0` | Returns the data schema for a prepared Agent Turn. |
| `Jido.Agent.Turn.validate/1` | Validates one Agent Turn. |

### `Jido.Agent.Ref`

Stable identity for one logical Agent.

| Function | Summary |
| --- | --- |
| `Jido.Agent.Ref.from_map/1` | Decodes and validates one exact version-1 Agent Ref map. |
| `Jido.Agent.Ref.from_map!/1` | Decodes one exact version-1 Agent Ref map or raises its validation error. |
| `Jido.Agent.Ref.new/1` | Creates and validates one Agent Ref. |
| `Jido.Agent.Ref.new!/1` | Creates one Agent Ref or raises its validation error. |
| `Jido.Agent.Ref.schema/0` | Returns the static schema for an Agent Ref. |
| `Jido.Agent.Ref.to_map/1` | Returns the exact version-1 public map for one Agent Ref. |
| `Jido.Agent.Ref.to_map!/1` | Returns the exact version-1 public map or raises its validation error. |
| `Jido.Agent.Ref.validate/1` | Validates one Agent Ref without changing its identity fields. |

### `Jido.Agent.Route`

Pure route normalization and selection.

This module has no public functions. Its struct is the contract.

### `Jido.Agent.Topology`

Logical members and output connections.

| Function | Summary |
| --- | --- |
| `Jido.Agent.Topology.bind/3` | Binds member inputs from one parent state snapshot. |
| `Jido.Agent.Topology.checks/3` | Reports connection proofs. |
| `Jido.Agent.Topology.connections_for/3` | Selects all declared output connections for one logical source and type. |
| `Jido.Agent.Topology.state/1` | Creates a symbolic reference to one parent Agent state field. |

### `Jido.Agent.Diff`

Final data differences.

| Function | Summary |
| --- | --- |
| `Jido.Agent.Diff.between/2` | Compares canonical Agent values; order and cancelled edits remain unambiguous. |
| `Jido.Agent.Diff.changed?/2` | True when one collection or the state changed. |
| `Jido.Agent.Diff.empty?/1` | True when neither data nor declaration order changed. |

### `Jido.Agent.View`

Builds a safe, framework-neutral view of one Agent.

| Function | Summary |
| --- | --- |
| `Jido.Agent.View.project/3` | Projects one Agent source as a JSON-safe map. |

## Actions, Instructions, and execution

Guides: [Actions](../actions/actions.md), [Execution](../flow-runtime/execution.md).

### `Jido.Action.Inline`

Compile-time inline Action support for host DSLs.

| Function | Summary |
| --- | --- |
| `Jido.Action.Inline.compile!/3` | Compiles a declaration with an explicit `name:` and no compiler options. |
| `Jido.Action.Inline.compile!/4` | Builds declaration and target AST inside a compiling owner module. |
| `Jido.Action.Inline.parse_bound!/3` | Parses named bindings, a binding list, a sole map binding, or `[]`. |
| `Jido.Action.Inline.parse_callback!/3` | Parses a named parameter variable or a map pattern for direct callback input. |
| `Jido.Action.Inline.setup!/1` | Installs owner hooks during module construction. |
| `Jido.Action.Inline.target!/2` | Returns the compiled Action for the owner's exact typed path. |

### `Jido.Action.Output`

Explicit envelope for successful Action outputs that are not normal maps.

| Function | Summary |
| --- | --- |
| `Jido.Action.Output.batch/2` | Builds an explicit batch output envelope. |
| `Jido.Action.Output.opaque/2` | Builds an explicit opaque output envelope. |
| `Jido.Action.Output.preserve/2` | Builds an output that applies the output schema and keeps its root shape. |
| `Jido.Action.Output.raw/2` | Builds an explicit raw output envelope. |
| `Jido.Action.Output.stream/2` | Builds an explicit stream output envelope. |

### `Jido.Instruction`

Defines the invocation value for one Action or Flow target.

| Function | Summary |
| --- | --- |
| `Jido.Instruction.bind/4` | Binds concrete call data to an inert Instruction template. |
| `Jido.Instruction.new/1` | Creates an Instruction from a map or keyword list. |
| `Jido.Instruction.new!/1` | Creates an Instruction or raises on failure. |
| `Jido.Instruction.resolve/3` | Resolves a target or Instruction and applies call-site data. |
| `Jido.Instruction.template/3` | Creates an inert Instruction template for a module target. |
| `Jido.Instruction.validate/1` | Validates the current target contract. |

### `Jido.Exec`

Compiles and runs Jido Actions and Flows with Runic.

| Function | Summary |
| --- | --- |
| `Jido.Exec.compile/2` | Compiles an Action, Instruction, Flow module, or Flow value to Runic. |
| `Jido.Exec.compile!/2` | Compiles an executable target to Runic or raises its error. |
| `Jido.Exec.effect_id/4` | Derives a stable identity for one deferred effect in a completed Runic output. |
| `Jido.Exec.result/2` | Projects one Runic execution observation to the `run/4` result contract. |
| `Jido.Exec.run/4` | Runs an Action or Flow to completion with the in-memory Runic runtime. |
| `Jido.Exec.supports?/2` | Returns true when an Action context supports the specified host capability. |

### `Jido.Exec.Wait`

Portable data for one suspended Flow wait.

| Function | Summary |
| --- | --- |
| `Jido.Exec.Wait.input/2` | Builds a portable input for one wait from a Signal. |
| `Jido.Exec.Wait.matches?/3` | Checks an event name and payload against this wait. |
| `Jido.Exec.Wait.new/1` | Creates and validates one portable wait value. |
| `Jido.Exec.Wait.next_deadline/1` | Returns the earliest timer deadline, or `nil`. |

### `Jido.Durable`

Runs and resumes persisted Flows from Signals without an Agent. Every operation
uses the persistence adapter of the named Jido instance.

| Function | Summary |
| --- | --- |
| `Jido.Durable.ref/2` | Builds a portable durable execution reference. |
| `Jido.Durable.start/4` | Starts or idempotently resumes one persisted Flow from a Signal. |
| `Jido.Durable.resume/3` | Continues a stored execution to its next durable stop. |
| `Jido.Durable.signal/5` | Saves one Signal for an addressed wait and continues the Flow. |
| `Jido.Durable.status/2` | Reads the last committed state, waits, and next wake time. |
| `Jido.Durable.result/2` | Reads the normal Exec result from the last committed state. |

### `Jido.Durable.Continuation`

Portable data for one suspended or terminal durable execution.

| Function | Summary |
| --- | --- |
| `Jido.Durable.Continuation.fingerprint/1` | Returns a stable fingerprint for one Flow definition and its loaded code. |
| `Jido.Durable.Continuation.portable/1` | Checks that a continuation contains only storage-safe terms. |
| `Jido.Durable.Continuation.validate/1` | Checks the exact shape of one continuation. |

## Flows and expressions

Guides: [Flows](../flows/flows.md), [Flow Data Definitions](../flow-data/flow-data.md).

### `Jido.Flow`

Defines the canonical Jido Flow data artifact and compile-time module DSL.

| Function | Summary |
| --- | --- |
| `Jido.Flow.decode_defaults/2` | Decodes JSON Flow defaults with the selected Flow input schema. |
| `Jido.Flow.dependencies/1` | Returns explicit, reference, and effective dependencies for each component. |
| `Jido.Flow.encode_defaults/2` | Encodes partial Flow defaults as JSON data after schema validation. |
| `Jido.Flow.explain/1` | Returns the versioned canonical inspection data for a Flow. |
| `Jido.Flow.from_action/1` | Builds the canonical one-step Flow for an Action module. |
| `Jido.Flow.from_action!/1` | Builds the canonical one-step Flow for an Action module, or raises. |
| `Jido.Flow.new/1` | Builds and validates one canonical Flow value from a data definition. |
| `Jido.Flow.new!/1` | Builds one canonical Flow value or raises its validation error. |
| `Jido.Flow.normalize_defaults/2` | Validates partial, portable input defaults for one Flow module. |
| `Jido.Flow.semantic_identity/1` | Returns the deterministic SHA-256 and UUIDv8 identity for a Flow. |
| `Jido.Flow.to_map/1` | Converts a Flow artifact to its deterministic semantic map. |
| `Jido.Flow.validate/1` | Validates the exact canonical Flow structure. |

### `Jido.Flow.Ref`

A portable reference in a canonical Flow expression.

| Function | Summary |
| --- | --- |
| `Jido.Flow.Ref.accumulator/1` | Builds a Reduce accumulator reference. |
| `Jido.Flow.Ref.body_result/1` | Builds an Iterate body result reference. |
| `Jido.Flow.Ref.context/1` | Builds a runtime context reference. |
| `Jido.Flow.Ref.input/1` | Builds a Flow input reference with a required path. |
| `Jido.Flow.Ref.item/1` | Builds a Map or Reduce item reference. |
| `Jido.Flow.Ref.item_id/0` | Builds a collection item identifier reference. |
| `Jido.Flow.Ref.item_index/0` | Builds a collection item index reference. |
| `Jido.Flow.Ref.iteration_index/0` | Builds an Iterate index reference. |
| `Jido.Flow.Ref.result/2` | Builds a named component result reference. |
| `Jido.Flow.Ref.select/2` | Appends a path to a reference after validating its source. |
| `Jido.Flow.Ref.state/1` | Builds an Iterate state reference. |

### `Jido.Flow.Inline`

Compiles an embedded Flow declaration for another module DSL.

| Function | Summary |
| --- | --- |
| `Jido.Flow.Inline.compile!/4` | Compiles one embedded Flow declaration. |
| `Jido.Flow.Inline.setup!/1` | Installs owner hooks during module construction. |
| `Jido.Flow.Inline.target!/2` | Returns the generated Flow module for an owner's exact typed path. |

### `Jido.Flow.Extension`

Defines compile-time macro extensions for the Flow module DSL.

This module has no public functions. Its struct is the contract.

### `Jido.Flow.Value`

Defines the canonical Flow value union.

| Function | Summary |
| --- | --- |
| `Jido.Flow.Value.validate_data/1` | Validates portable Flow data without references or expressions. |
| `Jido.Flow.Value.validate_object/1` | Validates a portable Flow metadata object. |

### `Jido.Expr`

Small, data-only expressions for limited use in Flow DSLs.

| Function | Summary |
| --- | --- |
| `Jido.Expr.evaluate/2` | Evaluates an expression tree with bounded fixed operations. |
| `Jido.Expr.expr/1` | Builds expression data from source; `^variable` inserts trusted host data. |
| `Jido.Expr.new/2` | Constructs an expression after checking its operator and operand arity. |
| `Jido.Expr.new!/2` | Constructs an expression, or raises `Jido.Expr.Error`. |
| `Jido.Expr.normalize/2` | Normalizes an expression or a data tree without evaluating operations. |
| `Jido.Expr.operations/0` | Returns the closed list of supported Elixir operators and arities. |
| `Jido.Expr.parse/2` | Parses quoted source with the shared, inert expression grammar. |
| `Jido.Expr.parse!/2` | Parses quoted source, or raises on a parse failure. |
| `Jido.Expr.reduce/4` | Reduces an expression or data tree with limits and exact paths. |
| `Jido.Expr.validate/2` | Validates a complete expression tree without running operations. |

## Signals

Guides: [Custom Signals](../signals/signals-and-custom-types.md), [Signal Bus](../signals/signal-bus-and-subscriptions.md).

### `Jido.Signal`

Defines the Jido event envelope.

| Function | Summary |
| --- | --- |
| `Jido.Signal.defined?/1` | Returns true when `module` was defined with `use Jido.Signal`. |
| `Jido.Signal.delete_context/2` | Deletes a CloudEvents extension context attribute. |
| `Jido.Signal.get_context/2` | Gets a CloudEvents extension context attribute. |
| `Jido.Signal.list_context/1` | Lists the CloudEvents extension context attribute names. |
| `Jido.Signal.new/1` | Creates a Signal from an attribute map or keyword list. |
| `Jido.Signal.new/3` | Creates a Signal with an explicit type, data value, and attributes. |
| `Jido.Signal.new!/1` | Creates a Signal and raises when its envelope is invalid. |
| `Jido.Signal.new!/3` | Creates a Signal with explicit type and data, or raises when it is invalid. |
| `Jido.Signal.put_context/3` | Adds a CloudEvents extension context attribute. |
| `Jido.Signal.schema/0` | Returns the Joi schema for the core Signal envelope. |

### `Jido.Signal.Context`

Validates CloudEvents extension context attributes.

| Function | Summary |
| --- | --- |
| `Jido.Signal.Context.delete/2` | Deletes one context attribute from a Signal. |
| `Jido.Signal.Context.delete_trace/1` | Deletes W3C, causation, and legacy trace attributes from a Signal. |
| `Jido.Signal.Context.ensure_trace/2` | Returns the Signal trace, or creates and stores a new root Trace. |
| `Jido.Signal.Context.get/2` | Gets one context attribute from a Signal. |
| `Jido.Signal.Context.get_trace/1` | Gets the valid Trace carried by a Signal. |
| `Jido.Signal.Context.names/1` | Lists the context attribute names on a Signal. |
| `Jido.Signal.Context.normalize/1` | Validates and normalizes a context attribute map. |
| `Jido.Signal.Context.put/3` | Adds one validated context attribute to a Signal. |
| `Jido.Signal.Context.put_trace/2` | Puts a valid Trace on a Signal. |
| `Jido.Signal.Context.trace_names/0` | Lists the Signal extension names used for Trace propagation. |

### `Jido.Signal.Codec`

Encodes and decodes Signals through the canonical CloudEvents map.

| Function | Summary |
| --- | --- |
| `Jido.Signal.Codec.deserialize/2` | Decodes one Signal or a list of Signals. |
| `Jido.Signal.Codec.from_map/1` | Parses a complete CloudEvents structured-mode map. |
| `Jido.Signal.Codec.serialize/2` | Encodes one Signal or a list of Signals. |
| `Jido.Signal.Codec.serialize!/2` | Encodes one Signal or a list of Signals, or raises. |
| `Jido.Signal.Codec.to_map/1` | Returns the canonical CloudEvents structured-mode map. |

### `Jido.Signal.Catalog`

Selects and validates explicitly registered Signal definitions.

| Function | Summary |
| --- | --- |
| `Jido.Signal.Catalog.decode/3` | Decodes one canonical wire map or binary and validates its definition. |
| `Jido.Signal.Catalog.new/1` | Builds a catalog from an explicit list of custom Signal modules. |
| `Jido.Signal.Catalog.new!/1` | Builds a catalog, or raises `Jido.Error.ValidationError`. |
| `Jido.Signal.Catalog.validate/2` | Revalidates an existing Signal without replacing its identity or metadata. |

### `Jido.Signal.Router`

Maps Signal type patterns to ordered targets.

| Function | Summary |
| --- | --- |
| `Jido.Signal.Router.add/2` | Adds one or more routes and preserves their registration order. |
| `Jido.Signal.Router.count/1` | Returns the number of registered Route values. |
| `Jido.Signal.Router.empty?/1` | Checks if a Router has no routes. |
| `Jido.Signal.Router.filter/2` | Filters Signals whose types match a route path pattern. |
| `Jido.Signal.Router.has_route?/2` | Checks if an exact route path is registered. |
| `Jido.Signal.Router.list/1` | Lists Routes in registration order. |
| `Jido.Signal.Router.matches?/2` | Checks if a Signal type matches a route path pattern. |
| `Jido.Signal.Router.merge/2` | Appends routes or another Router to a Router. |
| `Jido.Signal.Router.new/2` | Creates a Router from route specifications. |
| `Jido.Signal.Router.new!/2` | Creates a Router and raises for an invalid route specification. |
| `Jido.Signal.Router.normalize/1` | Normalizes and validates one or more route specifications. |
| `Jido.Signal.Router.path/1` | Resolves a route path. |
| `Jido.Signal.Router.remove/2` | Removes all routes that have one of the specified paths. |
| `Jido.Signal.Router.route/2` | Returns all targets whose route path and optional `Route.match` predicate match a Signal. |
| `Jido.Signal.Router.validate/1` | Validates one or more Route values with the Route Joi schema. |

### `Jido.Signal.Dispatch`

Validates dispatch targets and delivers Signals.

| Function | Summary |
| --- | --- |
| `Jido.Signal.Dispatch.dispatch/2` | Delivers a Signal to one target or a list of targets. |
| `Jido.Signal.Dispatch.validate_opts/1` | Validates one target tuple or a list of target tuples. |

### `Jido.Signal.Bus`

Provides ordered local publish and subscribe delivery for Signals.

| Function | Summary |
| --- | --- |
| `Jido.Signal.Bus.ack/3` | Acknowledges the current record for a durable subscription. |
| `Jido.Signal.Bus.child_spec/1` | Returns a child specification for a named Bus. |
| `Jido.Signal.Bus.delete_subscription/2` | Permanently removes a subscription and its durable cursor. |
| `Jido.Signal.Bus.publish/2` | Publishes Signals after the Store accepts all records. |
| `Jido.Signal.Bus.replay/3` | Reads retained records that match a signal-type path. |
| `Jido.Signal.Bus.start_link/1` | Starts a Bus linked to the caller. |
| `Jido.Signal.Bus.subscribe/3` | Adds a subscription for a signal-type path. |
| `Jido.Signal.Bus.unsubscribe/3` | Detaches a subscription target. |
| `Jido.Signal.Bus.via_tuple/2` | Returns the Registry tuple for a Bus name. |
| `Jido.Signal.Bus.whereis/2` | Finds a Bus by PID, name, or `{name, registry}` tuple. |

## Plugins

Guides: [Plugin Design](../plugins/plugin-design.md).

### `Jido.Plugin.Config`

Deferred environment references for Plugin options.

| Function | Summary |
| --- | --- |
| `Jido.Plugin.Config.env/1` | Creates a deferred reference without reading the environment. |
| `Jido.Plugin.Config.resolve/1` | Resolves environment references in Plugin option values. |

### `Jido.Plugin.Audit`

Stores bounded domain audit records in portable Agent state.

| Function | Summary |
| --- | --- |
| `Jido.Plugin.Audit.record/3` | Creates one domain audit Directive. |

### `Jido.Plugin.Scheduler`

Adds delayed and recurring Signals to an Agent.

| Function | Summary |
| --- | --- |
| `Jido.Plugin.Scheduler.cancel/1` | Creates one recurring schedule cancellation Directive. |
| `Jido.Plugin.Scheduler.cron/4` | Creates one recurring Signal Directive. |
| `Jido.Plugin.Scheduler.next_occurrence/3` | Returns the next UTC occurrence after one UTC instant. |
| `Jido.Plugin.Scheduler.occurrence_signal/5` | Builds one fresh recurring occurrence Signal. |
| `Jido.Plugin.Scheduler.schedule/2` | Creates one delayed Signal Directive. |

### `Jido.Plugin.SensorManager`

Keeps supervised sensor processes aligned with portable Agent state.

| Function | Summary |
| --- | --- |
| `Jido.Plugin.SensorManager.start/3` | Creates a Directive that adds or replaces one tagged sensor. |
| `Jido.Plugin.SensorManager.stop/1` | Creates a Directive that removes one tagged sensor. |

### `Jido.Agent.Plugin.FSM`

Adds deterministic finite-state route control to one Agent.

This module has no public functions. Its struct is the contract.

## Persistence

Guides: [Storage Model](../storage/persistence-storage-model.md).

### `Jido.Persistence`

Saves and restores portable Agent checkpoints through a persistence adapter.

| Function | Summary |
| --- | --- |
| `Jido.Persistence.delete_agent/4` | Logically deletes one Agent record with a compare-and-swap tombstone. |
| `Jido.Persistence.load_agent/4` | Loads and restores one Agent value. |
| `Jido.Persistence.load_agent_with_revision/4` | Loads and restores one Agent value with its stored revision. |
| `Jido.Persistence.resolve_config/2` | Resolves and validates a persistence adapter configuration. |
| `Jido.Persistence.restore/2` | Restores saved definition and state without consulting the source definition. |
| `Jido.Persistence.save_agent/3` | Saves one Agent checkpoint with an atomic revision check. |
| `Jido.Persistence.snapshot/2` | Captures the complete Agent as portable data without writing storage. |
| `Jido.Persistence.upgrade/3` | Runs an explicit data upgrade Action before resolving saved code references. |
| `Jido.Persistence.upgrade_agent/5` | Atomically upgrades one inactive saved Agent. |

### `Jido.Persistence.Store`

Shared byte storage boundary for Jido runtimes.

| Function | Summary |
| --- | --- |
| `Jido.Persistence.Store.compare_and_swap/4` | Atomically writes bytes when the supplied read condition still holds. |
| `Jido.Persistence.Store.open/1` | Validates a byte adapter and returns its normalized configuration. |
| `Jido.Persistence.Store.read/2` | Returns bytes and the condition from one read of a validated store. |

### `Jido.Persistence.Ecto.Migration`

Creates and removes the default Ecto persistence table.

| Function | Summary |
| --- | --- |
| `Jido.Persistence.Ecto.Migration.current_version/0` | Returns the latest migration version. |
| `Jido.Persistence.Ecto.Migration.down/1` | Reverses migrations through the selected version. |
| `Jido.Persistence.Ecto.Migration.up/1` | Runs migrations through the selected version. |

## Observability

Guides: [Telemetry Events](telemetry-event-reference.md), [Trace Context](../data/trace-context.md).

### `Jido.Telemetry`

The public runtime observability API.

| Function | Summary |
| --- | --- |
| `Jido.Telemetry.metrics/0` | Returns metric definitions for the Jido semantic event catalog. |
| `Jido.Telemetry.open_telemetry?/0` | Returns true when the optional OpenTelemetry mapping is active. |

### `Jido.Telemetry.AI`

The public observability API for AI Agent execution.

| Function | Summary |
| --- | --- |
| `Jido.Telemetry.AI.attach/3` | Attaches one handler to the complete event inventory. |
| `Jido.Telemetry.AI.attach_open_telemetry/1` | Attaches the vendor-neutral Agent, reasoning, tool, and ReqLLM OpenTelemetry bridges. |
| `Jido.Telemetry.AI.events/0` | Returns the complete AI Agent event inventory, including lower layers. |
| `Jido.Telemetry.AI.metrics/0` | Returns low-cardinality metrics for Agent, tool, and model operations. |
| `Jido.Telemetry.AI.open_telemetry?/0` | Returns true when optional OpenTelemetry mapping is active. |

### `Jido.Telemetry.AgentServer`

Owns the semantic event contract for AgentServer runtime work.

| Function | Summary |
| --- | --- |
| `Jido.Telemetry.AgentServer.event_names/0` | Returns every semantic AgentServer event name. |
| `Jido.Telemetry.AgentServer.point_metrics/0` | Returns the AgentServer point metric specifications. |
| `Jido.Telemetry.AgentServer.span_metrics/0` | Returns the AgentServer span metric specifications. |

### `Jido.Telemetry.Exec`

Emits semantic telemetry for Jido execution.

| Function | Summary |
| --- | --- |
| `Jido.Telemetry.Exec.event_names/0` | Returns all telemetry event names emitted by Jido Exec. |

### `Jido.Trace`

One validated W3C trace value for Jido.

| Function | Summary |
| --- | --- |
| `Jido.Trace.child/2` | Creates a child Trace with a new span ID. |
| `Jido.Trace.from_traceparent/2` | Parses a W3C version 00 traceparent value. |
| `Jido.Trace.metadata/1` | Returns the W3C carrier and semantic fields as one flat metadata map. |
| `Jido.Trace.new/1` | Creates a new root Trace. |
| `Jido.Trace.schema/0` | Returns the Joi schema for a Trace value. |
| `Jido.Trace.telemetry_context/1` | Returns the trace fields used as semantic telemetry metadata. |
| `Jido.Trace.to_traceparent/1` | Formats a Trace as a W3C version 00 traceparent value. |
| `Jido.Trace.valid?/1` | Checks a Trace struct or traceparent string. |
| `Jido.Trace.with_causation/2` | Returns a Trace with one causation identifier. |

## Data values

Guides: [Jido.Codec Documents](../data/versioned-documents.md), [Catalog and Discovery](../data/catalog.md), [Sessions and Threads](../data/sessions-and-threads.md), [Jido Error Contracts](../data/error-contracts.md).

### `Jido.Codec`

Compiles Joi-backed JSON codecs and routes trusted versioned documents.

| Function | Summary |
| --- | --- |
| `Jido.Codec.decode/2` | Decodes one trusted runtime document. |
| `Jido.Codec.decode_json/2` | Decodes one trusted runtime JSON document. |
| `Jido.Codec.encode/2` | Encodes one supported runtime value. |
| `Jido.Codec.encode_json/2` | Encodes one supported runtime value as JSON. |

### `Jido.Catalog`

A passive registry of explicitly registered values.

| Function | Summary |
| --- | --- |
| `Jido.Catalog.from_targets/3` | Builds an explicit Catalog from a map of references to values. |
| `Jido.Catalog.from_targets!/3` | Builds a Catalog from a compact target map or raises its error. |
| `Jido.Catalog.get/3` | Returns the exact Entry for a stable ID and version. |
| `Jido.Catalog.get_by_target/2` | Returns a registered Entry for a value. |
| `Jido.Catalog.list/1` | Lists all Entries in deterministic order. |
| `Jido.Catalog.new/1` | Builds an immutable Catalog from Entries or Manifests. |
| `Jido.Catalog.new!/1` | Builds an immutable Catalog or raises `ArgumentError`. |
| `Jido.Catalog.reference/2` | Returns a registered reference for a value. |
| `Jido.Catalog.resolve/2` | Resolves one exact registered reference. |

### `Jido.Catalog.Discovery`

Builds and atomically publishes the application-wide Catalog.

| Function | Summary |
| --- | --- |
| `Jido.Catalog.Discovery.catalog/0` | Returns the current immutable application-wide Catalog. |
| `Jido.Catalog.Discovery.get/2` | Returns a discovered entry for a stable identifier and `vsn`. |
| `Jido.Catalog.Discovery.get_by_target/1` | Returns a discovered registration for a value. |
| `Jido.Catalog.Discovery.included_plugins/0` | Lists the first-party Plugin modules included in this Jido release. |
| `Jido.Catalog.Discovery.list/0` | Lists all registered entries. |
| `Jido.Catalog.Discovery.ready?/0` | Returns true when the first Catalog build is complete. |
| `Jido.Catalog.Discovery.refresh/1` | Rebuilds and atomically replaces the complete Catalog and Codec index. |

### `Jido.Session`

A portable Agent Session that owns one `Jido.Thread`.

| Function | Summary |
| --- | --- |
| `Jido.Session.append/2` | Appends entries and returns the complete next Session. |
| `Jido.Session.close/1` | Closes the Session. |
| `Jido.Session.decode/1` | Decodes and validates a portable Session map. |
| `Jido.Session.decode!/1` | Decodes and validates a portable Session map or raises on invalid data. |
| `Jido.Session.encode/1` | Returns a versioned portable map. |
| `Jido.Session.from_thread/2` | Builds an open Session around an existing Thread. |
| `Jido.Session.new/1` | Creates an open Session with one empty Thread. |
| `Jido.Session.open?/1` | Returns true when the Session accepts entries. |
| `Jido.Session.put_metadata/2` | Replaces the portable Session metadata. |
| `Jido.Session.schema/0` | Returns the portable Session schema. |
| `Jido.Session.state_schema/0` | Returns the strict schema used when a Session is in Agent state. |

### `Jido.Thread`

A portable append-only Agent Thread.

| Function | Summary |
| --- | --- |
| `Jido.Thread.append/2` | Appends entries and returns the complete next Thread. |
| `Jido.Thread.decode/1` | Decodes and validates a portable Thread map. |
| `Jido.Thread.encode/1` | Returns a versioned portable map. |
| `Jido.Thread.entry_count/1` | Returns the number of entries. |
| `Jido.Thread.filter_by_kind/2` | Returns entries with one of the selected kinds. |
| `Jido.Thread.get_entry/2` | Returns one entry by its sequence number. |
| `Jido.Thread.last/1` | Returns the last entry or nil. |
| `Jido.Thread.new/1` | Creates an empty Thread. |
| `Jido.Thread.schema/0` | Returns the Thread schema. |
| `Jido.Thread.slice/3` | Returns entries in an inclusive sequence range. |
| `Jido.Thread.to_list/1` | Returns entries in chronological order. |

### `Jido.Id`

Creates the RFC 9562 UUID formats used by Jido.

| Function | Summary |
| --- | --- |
| `Jido.Id.compare_uuid7/2` | Compares the complete binary values of two valid UUIDv7 identifiers. |
| `Jido.Id.uuid7/0` | Returns a new UUIDv7 identifier. |
| `Jido.Id.uuid7?/1` | Returns true when the value is a valid UUIDv7 identifier. |
| `Jido.Id.uuid7_timestamp/1` | Returns the Unix millisecond timestamp in a valid UUIDv7 identifier. |
| `Jido.Id.uuid8/1` | Formats the first 16 bytes of a binary value as a UUIDv8 identifier. |

### `Jido.Error`

Unified error handling for the Jido ecosystem using Splode.

| Function | Summary |
| --- | --- |
| `Jido.Error.code/1` | Returns the registered Jido program code carried by an error. |
| `Jido.Error.config_error/2` | Creates a configuration validation error. |
| `Jido.Error.execution_error/2` | Creates an execution error. |
| `Jido.Error.internal_error/2` | Creates an internal error. |
| `Jido.Error.prefix_path/2` | Prefixes a structured error path. |
| `Jido.Error.prefix_result_path/2` | Prefixes the field path in a validation error result. |
| `Jido.Error.retryable?/1` | Returns whether an error is safe to retry by default. |
| `Jido.Error.routing_error/2` | Creates a routing error. |
| `Jido.Error.stable_codes/0` | Returns the closed set of Jido-owned program codes. |
| `Jido.Error.timeout_error/2` | Creates a timeout error. |
| `Jido.Error.to_map/1` | Converts an error into a stable, public map. |
| `Jido.Error.traverse_errors/2` | Traverses errors, calling `fun` for each leaf error, and returns a nested map of results grouped by each error's `path`. |
| `Jido.Error.type/1` | Returns the stable public type for an error. |
| `Jido.Error.unwrap!/2` | Raises an error if the result is an error, otherwise returns the result |
| `Jido.Error.validation_error/2` | Creates a validation error. |
| `Jido.Error.validation_result/4` | Creates a validation error result with a stable code and field path. |

## AI

Guides: [Graph-First AI Agents](../ai/graph-first-ai-agents.livemd), [Reasoning Matrix](reasoning-strategy-matrix.md).

### `Jido.AI.Reasoning`

Small inspection helpers for a graph-first AI Agent.

| Function | Summary |
| --- | --- |
| `Jido.AI.Reasoning.explain/1` | Returns the root Flow, schemas, defaults, and Agent-local tools. |
| `Jido.AI.Reasoning.preflight/2` | Validates one request and compiles its root Flow without execution. |
| `Jido.AI.Reasoning.root/1` | Returns the root reasoning Flow module. |

### `Jido.AI.Budget`

Checks portable request budgets before Jido AI starts more work.

| Function | Summary |
| --- | --- |
| `Jido.AI.Budget.before_model/2` | Checks all budgets before a model call starts. |
| `Jido.AI.Budget.remaining_elapsed_ms/2` | Returns the remaining request time in milliseconds. |
| `Jido.AI.Budget.resources/2` | Checks time, token, and cost budgets before another graph phase starts. |
| `Jido.AI.Budget.summary/2` | Returns a portable summary of used and configured budgets. |

### `Jido.AI.Usage`

Aggregates normalized usage across all model calls in one request.

| Function | Summary |
| --- | --- |
| `Jido.AI.Usage.add/2` | Adds one provider usage value to request totals. |
| `Jido.AI.Usage.cache_observation/3` | Returns provider-reported prompt-cache use for one model call. |
| `Jido.AI.Usage.normalize/1` | Normalizes provider usage and preserves reported numeric cost facts. |
| `Jido.AI.Usage.zero/0` | Returns a normalized zero usage value. |

### `Jido.AI.Toolset`

The tools selected for one AI Agent.

| Function | Summary |
| --- | --- |
| `Jido.AI.Toolset.definitions/1` | Builds ReqLLM definitions for an Agent Toolset. |
| `Jido.AI.Toolset.names/1` | Returns the model tool names in declaration order. |
| `Jido.AI.Toolset.provider_tool_choice/3` | Lowers semantic tool-use policy to one provider tool-choice value. |
| `Jido.AI.Toolset.requirement_satisfied?/3` | Checks whether one final answer satisfies semantic tool-use policy. |
| `Jido.AI.Toolset.resolve_call/2` | Resolves one portable model tool call against an Agent Toolset. |
| `Jido.AI.Toolset.select/2` | Selects a request tool subset below the protected Agent allowlist. |
| `Jido.AI.Toolset.validate/1` | Validates an ordered Agent Toolset. |
| `Jido.AI.Toolset.validate_call/2` | Validates one portable model tool call against an Agent Toolset. |

### `Jido.AI.ToolResult`

Separates a local Action result from bounded model-visible content.

| Function | Summary |
| --- | --- |
| `Jido.AI.ToolResult.normalize/2` | Normalizes one local Action outcome without putting its value in model context. |
| `Jido.AI.ToolResult.project/2` | Returns JSON-safe model content and size metadata. |

### `Jido.AI.Skill`

Loads trusted `SKILL.md` instructions through `Jido.AI.ToolSource`.

| Function | Summary |
| --- | --- |
| `Jido.AI.Skill.discover/1` | Discovers valid skills one directory level below each root. |
| `Jido.AI.Skill.load/2` | Loads one discovered skill by name. |
| `Jido.AI.Skill.source/1` | Builds a portable tool source for trusted skill roots. |

### `Jido.AI.Context`

The lifecycle boundary for one ReqLLM call.

| Function | Summary |
| --- | --- |
| `Jido.AI.Context.complete/3` | Attaches the exact ReqLLM result without changing the request. |
| `Jido.AI.Context.new/2` | Builds an open lifecycle around an existing ReqLLM context. |
| `Jido.AI.Context.prepare/2` | Freezes the exact ReqLLM model, context, and options for one call. |
| `Jido.AI.Context.schema/0` | Returns the Joi schema for a model-call context. |
| `Jido.AI.Context.transform/3` | Applies one idempotent transformation to the open ReqLLM context. |
| `Jido.AI.Context.validate/1` | Validates the lifecycle and its ReqLLM context. |

### `Jido.AI.Thread.Projection`

Projects the canonical `Jido.Session` Thread into portable model messages.

| Function | Summary |
| --- | --- |
| `Jido.AI.Thread.Projection.append/4` | Appends one portable model message to a Session. |
| `Jido.AI.Thread.Projection.breakpoint/1` | Returns the final included Thread sequence for one projection. |
| `Jido.AI.Thread.Projection.context/2` | Projects a Session into the canonical ReqLLM context and its decisions. |
| `Jido.AI.Thread.Projection.explain/2` | Projects a Thread and reports why each model message was included or excluded. |
| `Jido.AI.Thread.Projection.messages/1` | Projects complete model exchanges from a Session. |
| `Jido.AI.Thread.Projection.observe/5` | Appends one non-message observation to a Session. |
| `Jido.AI.Thread.Projection.project/2` | Projects a bounded set of complete conversation turns from a Session. |
| `Jido.AI.Thread.Projection.schema/0` | Returns the canonical Agent-state schema for a nullable Session. |

### `Jido.AI.InferenceClient.Selection`

Selects and validates the inference client for one AI operation.

| Function | Summary |
| --- | --- |
| `Jido.AI.InferenceClient.Selection.client!/1` | Returns the configured inference client for one action context. |

## Related

- [Module and Namespace Map](module-and-namespace-map.md)
- [Configuration Reference](configuration-reference.md)
- [Telemetry Events](telemetry-event-reference.md)
