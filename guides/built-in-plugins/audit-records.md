# Audit Records

This guide adds `Jido.Plugin.Audit` to an Agent so that selected domain facts commit in the same Turn as the state they describe.

The Plugin keeps a bounded list of records in Agent state. It starts no process and records nothing on its own. Your Action decides which facts matter and returns a record for each one. If the Turn fails, the record does not commit.

## Add the Plugin

Declare the Plugin and set `:max_entries`. The default is `1_000`. The value must be a positive integer, or the Agent definition fails. Plugin options in `use Jido.Agent` are a plain map.

```elixir
defmodule AuditGuide.ApproveInvoice do
  use Jido.Action,
    name: "audit_guide_approve_invoice",
    schema:
      Jido.Joi.object(%{
        invoice_id: Jido.Joi.string(),
        approver: Jido.Joi.string()
      })

  alias Jido.Plugin.Audit

  @impl Jido.Action
  def run(%{invoice_id: "disputed-" <> _}, _context), do: {:error, :invoice_disputed}

  def run(%{invoice_id: invoice_id, approver: approver}, context) do
    state = context.agent_state
    record = Audit.record({:invoice_approved, invoice_id}, :accepted, metadata: %{approver: approver})

    {:ok, %{state | approved: state.approved ++ [invoice_id]}, [record]}
  end
end

defmodule AuditGuide.Ledger do
  use Jido.Agent,
    name: "audit_guide_ledger",
    plugins: [{Jido.Plugin.Audit, %{max_entries: 2}}]

  state do
    schema Jido.Joi.object(%{approved: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    route "invoice.approve", AuditGuide.ApproveInvoice
  end
end
```

The Plugin owns the `:audit` key of Agent state. A new instance starts with an empty list:

```elixir
%{approved: [], audit: %{records: []}} = AuditGuide.Ledger.instantiate!(id: "ledger-1").state
```

## Record a domain fact

`Jido.Plugin.Audit.record/3` builds one `Jido.Plugin.Audit.Record`. Return it as a Directive with the new state, as `run/2` does above.

| Argument | Meaning |
|---|---|
| `event` | The domain fact. Any portable term. |
| `outcome` | An atom you choose, such as `:accepted` or `:rejected`. |
| `:id` option | A UUID7 string. Generated when omitted. |
| `:at` option | Unix time in milliseconds. Set to the current time when omitted. |
| `:metadata` option | A portable map. Defaults to `%{}`. |

Any other option raises `ArgumentError`.

## Read the records

Send three approvals to a live Agent. With `max_entries: 2`, only the newest two records remain, in the order they were recorded.

```elixir
{:ok, _instance} = Jido.start_link(name: AuditGuide.Jido)

{:ok, ledger} =
  Jido.start_agent(AuditGuide.Jido, AuditGuide.Ledger, id: "ledger-2")

:ok = Jido.AgentServer.await_ready(ledger)

approve = fn invoice_id ->
  Jido.Signal.new!(
    "invoice.approve",
    %{invoice_id: invoice_id, approver: "dana"},
    source: "/billing/approvals"
  )
end

for invoice_id <- ["inv-1", "inv-2", "inv-3"] do
  {:ok, _agent, _directives} = Jido.AgentServer.call(ledger, approve.(invoice_id))
end

{:ok, %{records: records}} = Jido.AgentServer.plugin_state(ledger, Jido.Plugin.Audit)

[{:invoice_approved, "inv-2"}, {:invoice_approved, "inv-3"}] = Enum.map(records, & &1.event)
%{outcome: :accepted, metadata: %{approver: "dana"}} = hd(records)
```

Domain state is not bounded by the Plugin. `approved` still holds all three invoices. The bound applies only to `audit.records`.

```elixir
["inv-1", "inv-2", "inv-3"] = Jido.AgentServer.snapshot(ledger).agent.state.approved
```

## Audit a failed Turn

A failed Turn commits nothing, so it adds no record. The same holds for a Flow that returns a record in a late step when an earlier step fails.

```elixir
{:error, %Jido.Error.ExecutionError{}} =
  Jido.AgentServer.call(ledger, approve.("disputed-9"))

{:ok, %{records: ^records}} = Jido.AgentServer.plugin_state(ledger, Jido.Plugin.Audit)
```

To keep a trail of failures, write it outside Agent state. The `error_policy:` start option accepts a two-argument function. It receives the error and a terminal summary map, and it must return `:continue` or `{:stop, reason}` with an atom reason. Any other result stops the Agent.

```elixir
audit_trail = self()

{:ok, watched} =
  Jido.start_agent(AuditGuide.Jido, AuditGuide.Ledger,
    id: "ledger-3",
    error_policy: fn _error, summary ->
      send(audit_trail, {:turn_failed, summary})
      :continue
    end
  )

:ok = Jido.AgentServer.await_ready(watched)

{:error, _error} = Jido.AgentServer.call(watched, approve.("disputed-10"))

summary =
  receive do
    {:turn_failed, summary} -> summary
  after
    1_000 -> raise "the error policy did not run"
  end

%{status: :failed, committed?: false} = summary
```

The summary carries `turn_id`, `signal_id`, `stage`, `duration_ms`, and the state versions before and after the Turn. It does not include the Signal data. The latest summary is also available without a policy function, as the `last_outcome` field of `Jido.AgentServer.status/2`.

```elixir
%{status: :failed, committed?: false} = Jido.AgentServer.status(watched).last_outcome
```

## Keep records portable

Before commit, the Plugin checks each record with `Jido.Plugin.Audit.Record.validate/1`. The event and metadata must contain only portable terms, the ID must be a UUID7, and the outcome must be an atom. A record that fails this check fails the Turn. The state change from that Turn does not commit either.

```elixir
{:error, %Jido.Error.ValidationError{details: %{path: [:record, :event]}}} =
  Jido.Plugin.Audit.Record.validate(Jido.Plugin.Audit.record(self(), :accepted))
```

See [Portable Values](../data/portable-values-and-references.md) for the rules.

## Limits

Records live in Agent state, so they last only as long as that state. They survive a restart only when the Agent uses persistence. Once `max_entries` is reached, each new record removes the oldest one. The Plugin is not an external compliance archive. Copy records to your own store when you must keep them beyond the bound.

## Related

- [Plugin State](../plugins/plugin-state-and-directives.md)
- [Make an Agent Durable](../durability/make-an-agent-durable.livemd)
- [Status and Turn History](../agent-servers/status-and-history.md)
