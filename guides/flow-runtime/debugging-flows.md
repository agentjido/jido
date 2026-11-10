# Debug Flows

This guide shows how to find out why a Flow failed, why a component did not run, or why a run is stuck. Start with the error. Move to the Flow definition, then to telemetry and the Runic workflow.

The examples use one Flow with a deliberate bug: `assign` reads a field that `lookup` does not return.

```elixir
defmodule DebugFlowsGuide.LookupTicket do
  use Jido.Action, name: "debug_flows_guide_lookup_ticket"

  @impl true
  def run(%{ticket_id: ticket_id}, _context), do: {:ok, %{ticket_id: ticket_id, priority: "high"}}
end

defmodule DebugFlowsGuide.AssignTicket do
  use Jido.Action,
    name: "debug_flows_guide_assign_ticket",
    schema: Jido.Joi.object(%{ticket_id: Jido.Joi.string(), owner: Jido.Joi.string()})

  @impl true
  def run(%{ticket_id: ticket_id, owner: owner}, _context), do: {:ok, %{ticket_id: ticket_id, owner: owner}}
end

defmodule DebugFlowsGuide.RouteTicket do
  use Jido.Flow, name: "debug_flows_guide_route_ticket"

  flow do
    step "lookup", action: DebugFlowsGuide.LookupTicket, params: %{ticket_id: input(:ticket_id)}

    step "assign",
      needs: ["lookup"],
      action: DebugFlowsGuide.AssignTicket,
      params: %{ticket_id: input(:ticket_id), owner: result("lookup", :owner)}

    output result("assign")
  end
end
```

## Read the error

Each Flow failure names its component, and each DSL Flow names its source line. Print the details before you add logging.

```elixir
{:error, error} = Jido.Exec.run(DebugFlowsGuide.RouteTicket, %{ticket_id: "t-9"})

%Jido.Error.ExecutionError{
  message: "flow reference path does not exist",
  details: %{
    node: "assign",
    node_path: ["assign"],
    reason: :missing_key,
    ref_type: :result,
    path: [:owner],
    segment: :owner,
    source: %{file: _file, line: _line}
  }
} = error
```

This says `assign` read `result("lookup", :owner)`, and the value has no `:owner` key. [Flow Errors](flow-errors.md) lists the fields for every failure.

A failed run does not log the node or the error, so read the returned error. See [Flow Security](flow-security.md#keep-secrets-out-of-logs) before you ship your logs anywhere.

## Inspect the definition

`Jido.Flow.dependencies/1` shows why each component waits. `needs` holds the explicit order, `references` holds the components read through `result`, and `effective` holds their union.

```elixir
flow = DebugFlowsGuide.RouteTicket.flow()

{:ok, dependencies} = Jido.Flow.dependencies(flow)

%{"lookup" => %{effective: []}, "assign" => %{needs: ["lookup"], references: ["lookup"], effective: ["lookup"]}} = dependencies
```

Source order creates no dependency. If two steps must run in order and neither reads the other, add `needs`.

`Jido.Flow.explain/1` returns the whole definition as data, with components in dependency order. Print it to see the target and params each component really has.

```elixir
{:ok, explained} = Jido.Flow.explain(flow)

["lookup", "assign"] = Enum.map(explained.components, & &1.name)
%{version: 1, kind: :flow, name: "debug_flows_guide_route_ticket", identity: %{digest: digest}} = explained
true = is_binary(digest)
```

`Jido.Flow.validate/1` checks the graph, references, and schemas without loading targets. `Jido.Exec.compile/2` also checks that targets exist and honor the Action contract. Run both on a Flow built from data to separate definition errors from runtime errors.

```elixir
{:ok, %Jido.Flow{}} = Jido.Flow.validate(flow)
{:ok, %Runic.Workflow{}} = Jido.Exec.compile(flow)

{:error, %Jido.Error.ValidationError{}} =
  Jido.Flow.new(%{
    name: "debug_flows_guide_bad_reference",
    components: [%{kind: :step, name: "assign", action: DebugFlowsGuide.AssignTicket, params: %{owner: Jido.Flow.Ref.result("missing")}}],
    output: Jido.Flow.Ref.result("assign")
  })
```

## Run one Action alone

`Jido.Exec.run/4` runs one Action through the same isolated path as a one-step Flow. Use it to test the Action away from the larger Flow.

```elixir
{:ok, %{ticket_id: "t-9", owner: "ana"}} =
  Jido.Exec.run(DebugFlowsGuide.AssignTicket, %{ticket_id: "t-9", owner: "ana"})

{:error, %Jido.Error.ValidationError{details: %{errors: [%{path: [:owner]} | _]}}} =
  Jido.Exec.run(DebugFlowsGuide.AssignTicket, %{ticket_id: "t-9"})
```

## Watch a run with telemetry

Attach a handler to the events from `Jido.Telemetry.Exec.event_names/0`. A run emits a Flow span and one Action span per attempt.

```elixir
defmodule DebugFlowsGuide.Trace do
  def handle_event(event, _measurements, metadata, owner) do
    send(owner, {:traced, event, Map.take(metadata, [:node_name, :attempt, :outcome, :retryable?, :error_type])})
  end
end

:telemetry.attach_many(
  "debug-flows-guide",
  Jido.Telemetry.Exec.event_names(),
  &DebugFlowsGuide.Trace.handle_event/4,
  self()
)

{:error, _error} = Jido.Exec.run(DebugFlowsGuide.RouteTicket, %{ticket_id: "t-9"})

:telemetry.detach("debug-flows-guide")

traced = fn traced, seen ->
  receive do
    {:traced, event, metadata} -> traced.(traced, [{event, metadata} | seen])
  after
    50 -> Enum.reverse(seen)
  end
end

events = traced.(traced, [])

[{[:jido, :flow, :start], _} | _] = events
[%{node_name: "lookup", outcome: :ok}, %{node_name: "assign", outcome: :error}] =
  for {[:jido, :action, :stop], metadata} <- events, do: metadata

{[:jido, :flow, :stop], %{outcome: :error, error_type: :execution_error, retryable?: false}} = List.last(events)
```

A retried Action emits a start and stop for each attempt, with `attempt` starting at 0. Normal errors end a span with `outcome: :error`. The `:exception` event is reserved for a raise, throw, or exit that escapes the span. An Action span covers resolving the component's params, so a failed reference shows up on the `assign` span even though its Action never ran.

Flow spans come from `Jido.Exec.run/4` only. Under a Runner, correlate `[:jido, :action, ...]` events with Runic's `[:runic, :runner, ...]` events through `runnable_id`. See [Telemetry Events](../reference/telemetry-event-reference.md).

## Inspect a live managed run

For a run under a `Runic.Runner`, ask the Runner what it is doing. Do not make these calls from inside a Worker hook.

| Question | Call |
| --- | --- |
| Is it finished? | `Jido.Exec.result/2` |
| Is anything running or did admission stop? | `Runic.Runner.admission_status/2` |
| Has its progress been saved? | `Runic.Runner.persistence_status/2` |
| What does its graph look like? | `Runic.Runner.get_workflow/2` |
| Is its Worker alive? | `Runic.Runner.lookup/2` |
| What runs under this Runner? | `Runic.Runner.list_workflows/1` |

To go through a run one unit at a time, start it with `dispatch_mode: :manual` and call `Jido.Exec.step/2`. See [Managed Execution](managed-execution.md#step-a-run-by-hand).

## Find common causes

| Symptom | Likely cause | Check |
| --- | --- | --- |
| `:missing_key` with `ref_type: :result` | The Action output lacks the field | `details.path`, the Action's `output_schema` |
| `:missing_key` with `ref_type: :context` | Context was not passed, or not passed again on resume | `details.path` |
| `"Action output validation must return a map"` from the Flow | `output` is a list or scalar | Wrap it: `output %{items: result("items")}` |
| `:unsupported_host` | A Flow with a wait ran outside a durable Agent | [Flow Waits](flow-waits.md) |
| `:execution_active` forever | A manual run needs another `step`, or an Action is blocked | `Runic.Runner.admission_status/2` |
| `:admission_stopped` | A failure elsewhere in the run stopped new units | `causes` from `Runic.Runner.admission_status/2` |
| `:non_portable_durable_value` | Managed data holds a PID, reference, port, or function | `details.path`, `details.type` |
| `:incompatible_target` | The Action module was reloaded after compile | Compile the Flow again |
| A run hangs under `Jido.Exec.run/4` | An Action blocks and no `:timeout` was set | Set `:timeout` |
| An Action ran several times | `max_attempts` retried it, or a resume restarted it | `attempt` in telemetry |
| A step ran earlier than expected | Source order creates no dependency | `Jido.Flow.dependencies/1` |

## Next steps

- [Flow Errors](flow-errors.md) lists each error and its fields.
- [Inspect Flows](../flow-data/flow-inspection.md) covers `Jido.Flow.explain/1` in depth.
- [Test Flows](testing-flows.livemd) turns a fixed bug into a regression test.
