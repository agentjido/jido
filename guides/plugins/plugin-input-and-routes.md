# Plugin Routing

A Plugin can give every Turn extra input, reject a Signal before it runs, choose among matching routes, and contribute routes of its own. This guide shows `prepare/2`, `admit/3`, `select_route/2`, and `derive_routes/1`.

## Prepare portable input

`prepare/2` runs before route selection, for every Signal, on both the pure and live paths. It receives a `Jido.Agent.Plugin.Preparation` and returns `{:ok, value}` or `{:error, reason}`. An error fails the Turn before any handler runs.

The handler reads the value at `context.plugin_inputs[plugin].prepared`, which is a `Jido.Plugin.Input`. The callback has no way to replace the Signal, the caller context, the route, or Agent state.

```elixir
defmodule PluginRouting.Tenant do
  use Jido.Plugin, option_keys: [agent: [:subject_prefix]]

  alias Jido.Agent.Plugin.Preparation

  @impl true
  def prepare(%Preparation{signal: signal}, opts) do
    prefix = Keyword.fetch!(opts, :subject_prefix)

    subject = signal.subject || ""

    case String.replace_prefix(subject, prefix, "") do
      tenant when tenant in ["", subject] -> {:error, :tenant_subject_required}
      tenant -> {:ok, %{tenant: tenant}}
    end
  end
end

defmodule PluginRouting.Invoice do
  use Jido.Agent,
    name: "invoice",
    plugins: [{PluginRouting.Tenant, %{subject_prefix: "tenant/"}}]

  state do
    schema Jido.Joi.object(%{tenant: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/billing/invoice"

    route "invoice.open", as: :open do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        %{tenant: tenant} = context.plugin_inputs[PluginRouting.Tenant].prepared
        {:ok, %{context.agent_state | tenant: tenant}}
      end
    end
  end
end

invoice = PluginRouting.Invoice.instantiate!(id: "inv-1")

acme =
  Jido.Signal.new!("invoice.open", %{}, source: "/billing/api", subject: "tenant/acme")

{:ok, %{state: %{tenant: "acme"}}, []} = PluginRouting.Invoice.cmd(invoice, acme)

no_subject = Jido.Signal.new!("invoice.open", %{}, source: "/billing/api")
{:error, :tenant_subject_required} = PluginRouting.Invoice.cmd(invoice, no_subject)
```

The prepared value must be portable data. A pid, a reference, or a function fails the Turn with `details.code` set to `:non_portable_term`. Use `admit/3` for a live value.

`Jido.Agent.Plugin.Preparation` has these fields: `:plugin`, `:agent_id`, `:agent_module`, `:agent_state`, `:signal`, `:plugin_state`, and `:route_candidates`. `:route_candidates` lists the routes that match the Signal, in order, and is empty when no route matches. `prepare/2` still runs in that case.

## Admit live input

`admit/3` runs only in `Jido.AgentServer`, after every `prepare/2`. It receives the Plugin's runtime process, or `nil` when the Plugin has none, followed by a `Jido.Plugin.Context.Admission` and its options.

It returns `{:ok, value}` to store a transient value at `context.plugin_inputs[plugin].runtime`, or `{:error, reason}` to reject the Turn. The value can hold any term. It does not enter Agent state, a checkpoint, or a Signal unless a handler copies portable data into its result.

```elixir
defmodule PluginRouting.ApiKey do
  use Jido.Plugin, option_keys: [agent_server: [:keys]]

  alias Jido.Plugin.Context.Admission

  @impl true
  def admit(_runtime, %Admission{caller_context: caller}, opts) do
    case Map.fetch(Map.new(opts[:keys]), caller[:api_key]) do
      {:ok, principal} -> {:ok, %{principal: principal, admitted_by: self()}}
      :error -> {:error, :invalid_api_key}
    end
  end
end

defmodule PluginRouting.Refund do
  use Jido.Agent,
    name: "refund",
    plugins: [{PluginRouting.ApiKey, %{keys: [{"k-1", "alice"}]}}]

  state do
    schema Jido.Joi.object(%{approved_by: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/billing/refund"

    route "refund.approve", as: :approve do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        case context.plugin_inputs[PluginRouting.ApiKey] do
          %{runtime: %{principal: principal}} ->
            {:ok, %{context.agent_state | approved_by: principal}}

          _pure_call ->
            {:error, :live_admission_required}
        end
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: PluginRouting.Jido)
{:ok, refunds} = Jido.start_agent(PluginRouting.Jido, PluginRouting.Refund, id: "refund-1")
:ok = Jido.AgentServer.await_ready(refunds)

approve = PluginRouting.Refund.approve_signal!(%{})

{:error, :invalid_api_key} = Jido.AgentServer.call(refunds, approve, context: %{api_key: "nope"})
%{state_version: 0} = Jido.AgentServer.snapshot(refunds)

{:ok, %{state: %{approved_by: "alice"}}, []} =
  Jido.AgentServer.call(refunds, approve, context: %{api_key: "k-1"})
```

A Plugin that keeps a credential in options should read [Supervised Resources](plugin-supervised-resources.livemd), which shows `Jido.Plugin.Config` and per-server options.

`admit/3` runs inside the Turn's budget, `turn_timeout`, and can be cancelled. It cannot make a synchronous request to its own AgentServer. That request returns `{:error, :reentrant_turn}`.

A raised exception or an invalid return value also rejects the Turn with a `Jido.Error.ExecutionError` that names the Plugin.

`Jido.Plugin.Context.Admission` has these fields: `:plugin`, `:agent_id`, `:agent_module`, `:signal`, `:caller_context`, `:plugin_state`, `:prepared_input`, and `:state_version`.

## Choose between prepare and admit

| Need | Callback |
|---|---|
| Value derived from the Signal or Agent state | `prepare/2` |
| Same behavior under `Jido.Agent.cmd/3` and in a live server | `prepare/2` |
| Value from a runtime process, or a value that is not portable | `admit/3` |
| Check that needs a secret or a live table | `admit/3` |

Each Plugin reads and writes its own input. One Plugin cannot replace another Plugin's input, and `admit/3` cannot replace its own `:prepared` value. `reduce/2` sees `:prepared` only, as `reduction.prepared_input`.

## Select a route

An Agent normally rejects two routes with the same path. When one Plugin defines `select_route/2`, routes can share a path as long as each has a unique `:as` alias. The callback receives a `Jido.Agent.Plugin.RouteSelection` and returns one of:

- `{:ok, alias}` to select one of `selection.candidates`.
- `:default` to keep the route when exactly one candidate matches.
- `{:error, reason}` to reject the Turn.

```elixir
defmodule PluginRouting.TierSelector do
  use Jido.Plugin

  alias Jido.Agent.Plugin.{Preparation, RouteSelection}

  @impl true
  def prepare(%Preparation{signal: signal}, _opts) do
    {:ok, %{tier: Map.get(signal.data, :tier, :standard)}}
  end

  @impl true
  def select_route(%RouteSelection{prepared_input: %{tier: :priority}}, _opts), do: {:ok, :priority}
  def select_route(%RouteSelection{candidates: [_only]}, _opts), do: :default
  def select_route(%RouteSelection{}, _opts), do: {:ok, :standard}
end

defmodule PluginRouting.AssignQueue do
  use Jido.Action,
    name: "assign_queue",
    schema: Jido.Joi.object(%{queue: Jido.Joi.string()})

  @impl true
  def run(%{queue: queue}, context), do: {:ok, %{context.agent_state | queue: queue}}
end

defmodule PluginRouting.Ticket do
  use Jido.Agent, name: "ticket", plugins: [PluginRouting.TierSelector]

  state do
    schema Jido.Joi.object(%{queue: Jido.Joi.string() |> Jido.Joi.default("none")})
  end

  routes do
    signal_source "/support/ticket"

    route "ticket.open", PluginRouting.AssignQueue, as: :standard, defaults: %{queue: "general"}
    route "ticket.open", PluginRouting.AssignQueue, as: :priority, defaults: %{queue: "urgent"}
    route "ticket.close", PluginRouting.AssignQueue, as: :close, defaults: %{queue: "closed"}
  end
end

ticket = PluginRouting.Ticket.instantiate!(id: "t-1")
open = fn data -> Jido.Signal.new!("ticket.open", data, source: "/support/api") end

{:ok, %{state: %{queue: "general"}}, []} = PluginRouting.Ticket.cmd(ticket, open.(%{}))
{:ok, %{state: %{queue: "urgent"}}, []} = PluginRouting.Ticket.cmd(ticket, open.(%{tier: :priority}))

close = Jido.Signal.new!("ticket.close", %{}, source: "/support/api")
{:ok, %{state: %{queue: "closed"}}, []} = PluginRouting.Ticket.cmd(ticket, close)
```

A selector returns only an alias, so it cannot supply a handler, a new Signal, or new state. These results fail the Turn with an error whose `details.code` names the problem:

| Result | `details.code` |
|---|---|
| `:default` with more than one candidate | `:ambiguous_route_selection` |
| `{:ok, alias}` that is not a candidate | `:invalid_route_selection` |
| Any other return value | `:plugin_invalid_callback_result` |

Only one Plugin on an Agent can define `select_route/2`. A Signal that matches no route fails with code `:unmatched_input`, and the selector does not run. See [Routes and Handlers](../agents/build-agent-routes.livemd) for route matching.

## Contribute routes

A Plugin adds routes by returning them from `derive_routes/1`, which receives the Plugin's data. A derived route needs an exact path, and the Agent keeps it alongside its own routes. An Agent can then handle a Signal that its definition never names.

```elixir
defmodule PluginRouting.PingAction do
  use Jido.Action, name: "ping", schema: Jido.Joi.object(%{})

  @impl true
  def run(_params, context), do: {:ok, %{context.agent_state | pings: context.agent_state.pings + 1}}
end

defmodule PluginRouting.Ping do
  use Jido.Plugin

  @impl true
  def derive_routes(data) do
    [
      %{
        path: Map.fetch!(data, :path),
        as: :ping,
        handler: %{kind: :action, target: PluginRouting.PingAction}
      }
    ]
  end
end

defmodule PluginRouting.Monitored do
  use Jido.Agent, name: "monitored", plugins: [{PluginRouting.Ping, %{path: "health.ping"}}]

  state do
    schema Jido.Joi.object(%{pings: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end
end

monitored = PluginRouting.Monitored.instantiate!(id: "m-1")
ping = Jido.Signal.new!("health.ping", %{}, source: "/health")
{:ok, %{state: %{pings: 1}}, []} = PluginRouting.Monitored.cmd(monitored, ping)
```

## Related

- [Agent Turns and Replies](../agents/turns-state-and-replies.md) describes the Turn these callbacks join.
- [Action Context](../actions/action-context.md) lists the fields that a handler receives.
- [Admission and Deadlines](../agent-servers/agent-server-admission.md) covers the server's own admission rules.
