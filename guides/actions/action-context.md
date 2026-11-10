# Action Context

This guide shows what the second argument of `run/2` contains and how to supply it. Context carries caller-owned data that is not part of the Action input, such as a tenant, a user, or a gateway module.

## Pass context

`Jido.Exec.run/4` takes context as its third argument. It can be a map, a keyword list, or `nil`. The Action receives a map.

```elixir
defmodule Support.AssignTicket do
  alias Jido.Joi

  use Jido.Action,
    name: "assign_ticket",
    schema: Joi.object(%{ticket_id: Joi.string()})

  @impl true
  def run(%{ticket_id: ticket_id}, %{tenant_id: tenant_id}) do
    {:ok, %{ticket_id: ticket_id, tenant_id: tenant_id}}
  end

  def run(_params, _context), do: {:error, :tenant_required}
end

{:ok, %{ticket_id: "t-1", tenant_id: "acme"}} =
  Jido.Exec.run(Support.AssignTicket, %{ticket_id: "t-1"}, %{tenant_id: "acme"})

{:ok, %{tenant_id: "globex"}} =
  Jido.Exec.run(Support.AssignTicket, %{ticket_id: "t-1"}, tenant_id: "globex")

{:error, %Jido.Error.ExecutionError{details: %{reason: :tenant_required}}} =
  Jido.Exec.run(Support.AssignTicket, %{ticket_id: "t-1"})
```

Jido does not validate context against a schema. Match the keys you require in the `run/2` head, as this example does, and give a fallback clause that returns an error. Without that clause, a missing key raises `FunctionClauseError`, which Exec reports as a retryable `Jido.Error.ExecutionError`.

## Choose params or context

| Use | For |
|---|---|
| Params | The data this call acts on. The schema validates it. A Flow can compute it from earlier steps. |
| Context | Data about the caller or environment. It is shared by every Action in the run. |

A value that changes what the Action does belongs in params, because a schema can check it and a contract can describe it. A value that says who is calling or which dependency to use belongs in context.

## Inject a dependency

Pass a module through context to replace a dependency in tests or per tenant.

```elixir
defmodule Support.Mailer do
  def deliver(ticket_id), do: {:ok, "live-" <> ticket_id}
end

defmodule Support.StubMailer do
  def deliver(ticket_id), do: {:ok, "stub-" <> ticket_id}
end

defmodule Support.NotifyCustomer do
  use Jido.Action, name: "notify_customer"

  @impl true
  def run(%{ticket_id: ticket_id}, context) do
    mailer = Map.get(context, :mailer, Support.Mailer)

    with {:ok, receipt} <- mailer.deliver(ticket_id) do
      {:ok, %{receipt: receipt}}
    end
  end
end

{:ok, %{receipt: "live-t-1"}} = Jido.Exec.run(Support.NotifyCustomer, %{ticket_id: "t-1"})

{:ok, %{receipt: "stub-t-1"}} =
  Jido.Exec.run(Support.NotifyCustomer, %{ticket_id: "t-1"}, %{mailer: Support.StubMailer})
```

Immediate execution accepts any term in context, including a pid or a function. Durable execution does not. See [Keep context portable for durable execution](#keep-context-portable-for-durable-execution).

## Bind context to an Instruction

An Instruction can hold context. Context given at the call replaces equal keys. See [Instructions and Targets](instructions.md).

```elixir
instruction =
  Jido.Instruction.new!(target: Support.AssignTicket, context: %{tenant_id: "acme"})

{:ok, %{tenant_id: "acme"}} = Jido.Exec.run(instruction, %{ticket_id: "t-1"})
{:ok, %{tenant_id: "globex"}} = Jido.Exec.run(instruction, %{ticket_id: "t-1"}, %{tenant_id: "globex"})
```

## Read context in a Flow

Every Action in a Flow receives the same run context. A Flow can also copy a context value into a step's params with `context/1`.

```elixir
defmodule Support.TicketReport do
  use Jido.Action, name: "ticket_report"

  @impl true
  def run(params, context), do: {:ok, %{from_params: params.tenant, from_context: context.tenant_id}}
end

defmodule Support.ReportFlow do
  use Jido.Flow, name: "report_flow"

  flow do
    step "report", action: Support.TicketReport, params: %{tenant: context(:tenant_id)}
    output result("report")
  end
end

{:ok, %{from_params: "acme", from_context: "acme"}} =
  Jido.Exec.run(Support.ReportFlow, %{}, %{tenant_id: "acme"})
```

## Read Agent data in a Turn

An Agent adds its own values when it runs a route. Actions usually read `agent_state` to build the next state.

| Key | Value | Set by |
|---|---|---|
| `:agent_id` | The Agent instance ID | `cmd/3` and `Jido.AgentServer` |
| `:agent_module` | The Agent module | `cmd/3` and `Jido.AgentServer` |
| `:agent_signal_source` | The source for Signals that the Agent builds | `cmd/3` and `Jido.AgentServer` |
| `:agent_state` | The current Agent state | `cmd/3` and `Jido.AgentServer` |
| `:agent_topology` | The declared Agent topology | `cmd/3` and `Jido.AgentServer` |
| `:plugin_inputs` | Values prepared by Plugins for this Turn | `cmd/3` and `Jido.AgentServer` |
| `:signal` | The input Signal | `cmd/3` and `Jido.AgentServer` |
| `:turn_id` | The Turn identifier | `Jido.AgentServer` |
| `:trace_context` | The Turn trace | `Jido.AgentServer` |

Pass your own values with the `:context` option. They merge with these keys. A caller that supplies a reserved Agent key gets an error instead of replacing the value.

```elixir
defmodule Support.CountTicket do
  use Jido.Action, name: "count_ticket"

  @impl true
  def run(_params, context) do
    state = %{context.agent_state | handled: context.agent_state.handled + 1}
    {:ok, Map.put(state, :last_shift, context.shift)}
  end
end

defmodule Support.QueueAgent do
  use Jido.Agent, name: "support_queue"

  state do
    schema Jido.Joi.object(%{
             handled: Jido.Joi.integer() |> Jido.Joi.default(0),
             last_shift: Jido.Joi.string() |> Jido.Joi.optional()
           })
  end

  routes do
    signal_source "/support/queue"
    route "ticket.handled", Support.CountTicket
  end
end

agent = Support.QueueAgent.instantiate!(id: "queue-1", state: %{handled: 1})
signal = Jido.Signal.new!("ticket.handled", %{}, source: "/support")

{:ok, next, []} = Support.QueueAgent.cmd(agent, signal, context: %{shift: "night"})
%{handled: 2, last_shift: "night"} = next.state

{:error, _reserved_key_error} = Support.QueueAgent.cmd(agent, signal, context: %{signal: :mine})
```

## Reserved keys

Exec strips these keys from the context it passes to `run/2`:

- `:jido_exec_capabilities`
- `:__jido_exec_durable__`
- `:__jido_exec_max_concurrency__`
- `:__jido_wait_host__`
- `:__jido_wait_result__`

A `context()` reference in a Flow reads the same context without these keys.

A caller cannot grant a capability by setting the key. Only the execution host can set it. Ask for a capability with `Jido.Exec.supports?/2`.

```elixir
defmodule Support.RequestReview do
  use Jido.Action, name: "request_review"

  @impl true
  def run(_params, context), do: {:ok, %{can_wait: Jido.Exec.supports?(context, :waits)}}
end

{:ok, %{can_wait: false}} = Jido.Exec.run(Support.RequestReview)

{:ok, %{can_wait: false}} =
  Jido.Exec.run(Support.RequestReview, %{}, %{jido_exec_capabilities: [:waits]})
```

`:waits` is the only capability. Immediate `Jido.Exec.run/4` does not offer it. See [Flow Waits](../flow-runtime/flow-waits.md).

## Keep context portable for durable execution

`Jido.Durable` rejects params, metadata, or context that holds a pid, port, reference, or function, with `reason: :non_portable_durable_value`. Direct Runic execution does not store runtime context, so pass the same context again when you resume. See [Direct Runic Execution](../flow-runtime/managed-execution.md).

Prefer a registered name or a module to a pid when an Action can move to durable execution.

## Keep secrets out of context

`Jido.Exec.run/4` does not write Runic's failure warning to the logs, so a failed Action does not print its params or context. The returned error, Runic Workflows, and stored data can still hold them. Do not place API keys or tokens in either one. Pass a module or a name, and have the Action read the secret from its own store.

Telemetry metadata for Actions does not include params, context, or results. See [Telemetry and Tracing](../operations/telemetry-tracing-and-logs.md).

## Related

- [Instructions and Targets](instructions.md)
- [Agent Turns and Replies](../agents/turns-state-and-replies.md)
- [Test Actions](testing-actions.livemd)
