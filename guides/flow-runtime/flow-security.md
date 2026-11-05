# Flow Security

This guide explains what Jido enforces when it runs a Flow and what stays your responsibility. Read it before you run Flows from stored definitions, accept input from outside your system, or let an Action choose the next target.

Jido gives you bounded data and validated calls. It has no concept of a user, and no authorization checks. An Action runs with the full rights of your application.

## Know what stored Flows can contain

A Flow is data. Map definitions and stored JSON cannot hold code: `Jido.Flow.new/1` and `Jido.Codec.decode/2` reject anonymous functions, MFA tuples, and step bodies. Expressions use `Jido.Expr`, which has a fixed set of operators, no application calls, and resource limits that apply to each call. Only compile-time source can add code. `Jido.Flow.Inline` documents the same rule: its inputs are trusted source, so never pass stored or runtime data to it.

```elixir
{:error, %Jido.Error.ValidationError{}} =
  Jido.Flow.new(%{
    name: "flow_security_guide_rejects_function",
    components: [],
    output: %{value: fn -> :run_this end}
  })
```

A stored Flow is still a program. It decides which Actions run, in what order, and with which params. Treat permission to write a Flow definition as permission to call every Action in the Catalog.

## Limit targets with a Catalog

Stored JSON names targets by stable ID and version. `Jido.Codec.decode/2` resolves each one through a `Jido.Catalog`, so a document cannot name a module directly. A Catalog built for one purpose is an allow-list. A Flow that names anything else fails to decode.

```elixir
defmodule FlowSecurityGuide.ReadInvoice do
  use Jido.Action, name: "flow_security_guide_read_invoice"

  @impl true
  def run(%{invoice_id: invoice_id}, _context), do: {:ok, %{invoice_id: invoice_id}}
end

defmodule FlowSecurityGuide.RefundInvoice do
  use Jido.Action, name: "flow_security_guide_refund_invoice"

  @impl true
  def run(%{invoice_id: invoice_id}, _context), do: {:ok, %{refunded: invoice_id}}
end

refund_flow =
  Jido.Flow.new!(%{
    name: "flow_security_guide_refund",
    components: [
      %{kind: :step, name: "refund", action: FlowSecurityGuide.RefundInvoice, params: %{invoice_id: Jido.Flow.Ref.input(:invoice_id)}}
    ],
    output: Jido.Flow.Ref.result("refund")
  })

shared_entries = %{
  {"billing.read_invoice", 1} => {:action, FlowSecurityGuide.ReadInvoice},
  {"guide.any_map", 1} => {:schema, refund_flow.schema},
  {"guide.invoice_id", 1} => {:atom, :invoice_id}
}

read_only_catalog = Jido.Catalog.from_targets!(FlowSecurityGuide, :jido, shared_entries)

full_catalog =
  Jido.Catalog.from_targets!(
    FlowSecurityGuide,
    :jido,
    Map.put(shared_entries, {"billing.refund_invoice", 1}, {:action, FlowSecurityGuide.RefundInvoice})
  )

codec_options = [codec: Jido.Flow.Codec]

{:ok, stored_json} = Jido.Codec.encode_json(refund_flow, [catalog: full_catalog] ++ codec_options)

{:ok, %Jido.Flow{}} = Jido.Codec.decode_json(stored_json, [catalog: full_catalog] ++ codec_options)
{:error, [_issue | _]} = Jido.Codec.decode_json(stored_json, [catalog: read_only_catalog] ++ codec_options)
```

Atoms and schemas are Catalog entries too, so a stored document cannot create new atoms or reference a schema you did not list.

Finding an entry does not authorize its target. Decide who may run a decoded Flow before you pass it to `Jido.Exec.run/4`. Use several narrow Catalogs if different callers get different Actions.

Without a `:catalog` option, the codec uses the published Catalog from `Jido.Catalog.Discovery`. By default, that scan covers every loaded application, so any listed module becomes a possible target. When users can supply definitions, pass an explicit Catalog or set an application allow-list.

<!-- partial -->
```elixir
config :jido, Jido.Catalog.Discovery,
  applications: [:my_app]
```

The decoder also bounds what it reads. A document may be at most 8 MiB as JSON by default, which you can change with `:maximum_json_bytes`. It may have at most 100 levels of nesting, 10,000 entries in a collection, and 100,000 nodes in total. A Catalog holds at most 10,000 entries.

## Validate input at the boundary

Give each Flow a `schema`. `Jido.Exec.run/4` and `Jido.Exec.start/6` validate input before any Action runs. Each Action validates its own params, and output schemas validate results. Schemas check shape, not permission. Check that the caller may act on `invoice_id` inside an Action or before the call.

Flow input is data, so references resolve to values and are never evaluated. A `Jido.Expr` value inside input stays inert. Do not build a Flow definition by placing untrusted strings into `name`, `event`, or target fields.

## Trust context from your own code

Context belongs to the caller of `Jido.Exec.run/4`. Every Action in the run reads it as its second argument, and any Flow component can reference it with `context(:key)`. Set it from verified session data, and never copy it from a request body.

Jido removes reserved execution keys from caller and Instruction context. A caller cannot claim host capabilities such as waits, even by passing them in context.

```elixir
defmodule FlowSecurityGuide.ReadCapabilities do
  use Jido.Action, name: "flow_security_guide_read_capabilities"

  @impl true
  def run(_params, context) do
    {:ok, %{waits?: Jido.Exec.supports?(context, :waits), tenant: context.tenant}}
  end
end

{:ok, %{waits?: false, tenant: "acme"}} =
  Jido.Exec.run(FlowSecurityGuide.ReadCapabilities, %{}, %{tenant: "acme", jido_exec_capabilities: [:waits]})
```

## Control dynamic targets

An Invoke expander returns `{:continue, input, target}`, and a Handoff selector returns `{:handoff, input, target}`. Whatever module that Action returns will be resolved and, for Invoke, run. Jido checks the target contract. It does not check a Catalog here. If model output or user input influences the choice, map it through a fixed table, as below, and never convert a string to a module.

```elixir
defmodule FlowSecurityGuide.ChooseTool do
  use Jido.Action, name: "flow_security_guide_choose_tool"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule FlowSecurityGuide.ExpandTool do
  use Jido.Action, name: "flow_security_guide_expand_tool"

  @allowed %{"read_invoice" => FlowSecurityGuide.ReadInvoice}

  @impl true
  def run(%{tool: tool, arguments: arguments}, _context) do
    case Map.fetch(@allowed, tool) do
      {:ok, target} -> {:continue, arguments, target}
      :error -> {:error, Jido.Error.execution_error("tool is not allowed", %{reason: :tool_not_allowed, retry: false})}
    end
  end
end

defmodule FlowSecurityGuide.RunTool do
  use Jido.Flow, name: "flow_security_guide_run_tool"

  flow do
    invoke "tool",
      decision: FlowSecurityGuide.ChooseTool,
      expander: FlowSecurityGuide.ExpandTool,
      params: %{tool: input(:tool), arguments: input(:arguments)}

    output result("tool")
  end
end

{:ok, %{invoice_id: "inv-5"}} =
  Jido.Exec.run(FlowSecurityGuide.RunTool, %{tool: "read_invoice", arguments: %{invoice_id: "inv-5"}})

{:error, %{details: %{reason: :tool_not_allowed}}} =
  Jido.Exec.run(FlowSecurityGuide.RunTool, %{tool: "refund_invoice", arguments: %{invoice_id: "inv-5"}})
```

A Handoff target cannot carry bound context or metadata. A context bound in an Invoke target's Instruction cannot claim capabilities. See [Dynamic Flows](../flows/dynamic-flows.md).

## Control who can resolve a wait

`Jido.AgentServer.deliver_wait/4` checks that the Signal matches the wait's event and `match` fields. That is correlation, not authorization. Anyone who can reach the function with the right ID and fields can resolve the wait. Authenticate the sender before you call it, and put the identity of the expected approver in `match` where you can. See [Flow Waits](flow-waits.md).

## Bound resource use

| Resource | Bound | Your control |
| --- | --- | --- |
| Time per attempt | None by default | `:timeout` |
| Attempts | 1 | `:max_attempts` |
| Concurrent Flow work | The smaller of schedulers and 10 | `:max_concurrency` |
| Iterate | 1 to 10,000 iterations, required | `max_iterations` or `repeat` |
| Map and Reduce collection size | None | Validate length in the Flow schema |
| Accepted wait inputs | 1,024 per execution | Fixed |
| Concurrent runs | None by default | A `Task.Supervisor` with `max_children`, passed as `:task_supervisor` |

`Jido.Exec.run/4` waits with no caller-side limit, so an Action without a `:timeout` can hold the caller until it stops. Check collection size for any input you do not control.

## Keep secrets out of logs

Jido's telemetry start and stop metadata omits params, context, results, and full errors. Other outputs can include your values:

- **Failure logs.** When a node fails, Runic logs a warning that prints the node and the error, and both can hold your values. `Jido.Exec.run/4`, `Jido.Exec.start/6`, `Jido.Exec.resume/4`, `cmd/3`, and a live AgentServer keep this line out of the logs. Code that calls `Runic.Workflow.execute/3` itself still gets it.
- **Error details.** An exception message, `details.return` for an invalid return, and `details.reason` can hold values from your code. For a raised exception, `details.stacktrace` can hold call arguments, for example after a `FunctionClauseError`. `Jido.Error.to_map/1` omits the stacktrace and bounds the other details.
- **Stored data.** A managed run or durable Turn stores Flow input and Action results. Runic does not persist runtime context. A durable Turn saves its caller context in its continuation record, and Instruction context on an Action target is cleared from a managed Workflow. A value copied from context into an Action's output is stored as a result. A live Workflow from `Runic.Runner.get_workflow/2` holds the run's context in memory, so do not log it.

Do these in production:

- Fetch secrets inside the Action, from your own secret store, and do not return them.
- Pass a credential reference in context, not the credential.
- Add a Logger filter, or lower the level, if your logs leave your trust boundary.
- Call `Jido.Error.to_map/1` before you log an error or return it to a client, and return only the fields that client needs.
- Encrypt the Store if Flow input or Action results are sensitive.

## Protect stored runs

A Store's contents decide what a resumed run does next. Limit who can write to it. `Jido.Exec.start/6` rejects PIDs, ports, references, and functions in params, context, and metadata. That check is for portability and it does not filter secrets or malicious data.

An Action module that changes after a graph is built fails with `details.reason: :incompatible_target` instead of running new code against the old graph. A durable Turn compares a fingerprint of its Flow and loaded code in the same way. See [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd).

## Check your setup

- Each Flow from outside your code decodes through a Catalog limited to what its author may call.
- Your code authorizes the caller before `Jido.Exec.run/4`, `Jido.Exec.start/6`, and `Jido.AgentServer.deliver_wait/4`.
- Each Flow has an input schema, and it bounds list lengths for untrusted collections.
- Invoke and Handoff targets come from a fixed table.
- Each external call has a `:timeout`, and non-idempotent Actions return `retry: false` or dedupe with `Jido.Exec.effect_id/4`.
- No secret appears in params, Action output, or a logged error.

## Next steps

- [Store Flows as JSON](../flow-data/flow-storage.md) covers Catalogs and documents.
- [Action Context](../actions/action-context.md) covers what an Action sees.
- [Flow Errors](flow-errors.md) lists the fields your logs may contain.
