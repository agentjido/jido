# Transforms and Forwards

Use a transform to turn one Signal into another, and a forward to pass a Signal to another Agent. Neither runs an Action or changes Agent state.

Both are terminal routes. The route body holds only the handler, and the Turn returns the source state with one Directive.

## Forward a Signal

`forward to: agent(name)` sends the unchanged Signal to a named topology member. `forward to: parent()` sends it to the current parent.

```elixir
defmodule ForwardGuide.BillingDesk do
  use Jido.Agent, name: "billing_desk"

  routes do
    route "ticket.billing", as: :handle do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

defmodule ForwardGuide.TicketRouter do
  use Jido.Agent, name: "ticket_router"

  routes do
    route "ticket.billing" do
      forward to: agent(:billing)
    end

    route "ticket.escalate" do
      forward to: parent()
    end
  end

  topology do
    agent :billing, ForwardGuide.BillingDesk
  end
end

router = ForwardGuide.TicketRouter.instantiate!(id: "router-1")

billing = Jido.Signal.new!("ticket.billing", %{ticket_id: "t-7"}, source: "/helpdesk")
{:ok, same, [send_to_member]} = ForwardGuide.TicketRouter.cmd(router, billing)

%Jido.Agent.Directive.AgentSend{name: :billing, signal: ^billing} = send_to_member
true = same.state == router.state

escalate = Jido.Signal.new!("ticket.escalate", %{ticket_id: "t-7"}, source: "/helpdesk")
{:ok, _same, [%Jido.Agent.Directive.ParentSend{signal: ^escalate}]} =
  ForwardGuide.TicketRouter.cmd(router, escalate)
```

The destination is portable definition data. It holds a logical name, never a PID or a transport.

A forward target is checked when the definition is built:

```elixir
parent_route = %{path: "ticket.up", handler: %{kind: :forward, target: %{kind: :parent}}}
member_route = fn name -> %{path: "ticket.down", handler: %{kind: :forward, target: %{kind: :agent, name: name}}} end

{:error, %Jido.Error.ValidationError{code: :unknown_forward_target}} =
  Jido.Agent.define(%{name: "bad_router", routes: [member_route.(:billing)]})

{:error, %Jido.Error.ValidationError{code: :self_forward}} =
  Jido.Agent.define(%{name: "bad_router", routes: [member_route.(:root)]})

{:ok, _definition} = Jido.Agent.define(%{name: "good_router", routes: [parent_route]})
```

Delivery is a runtime step. `Jido.Agent.cmd/3` returns the Directive and sends nothing. An AgentServer rejects a Turn whose `ParentSend` has no parent or whose `AgentSend` has no activation to look up members. See [Parent and Child Agents](../composition/parent-and-child-agents.md).

## Transform a Signal

A `transform` receives the complete `Jido.Signal` and returns `{:ok, signal}` or `{:error, reason}`. Jido wraps the new Signal in a `Jido.Agent.Directive.Emit`.

Update the Signal you received when you want to keep its envelope, or build a new one.

```elixir
defmodule TransformGuide.WebhookAgent do
  use Jido.Agent, name: "webhook_adapter"

  routes do
    route "webhook.ticket.created", as: :ticket_created do
      transform signal do
        case signal.data do
          %{"subject" => subject} when is_binary(subject) ->
            {:ok, %{signal | type: "ticket.opened", data: %{subject: String.trim(subject)}}}

          _other ->
            {:error, :missing_subject}
        end
      end
    end

    route "webhook.ticket.closed" do
      transform %Jido.Signal{data: %{"id" => id}} do
        Jido.Signal.new("ticket.closed", %{ticket_id: id}, source: "/webhooks")
      end
    end
  end
end

adapter = TransformGuide.WebhookAgent.instantiate!(id: "webhook-1")

created = Jido.Signal.new!("webhook.ticket.created", %{"subject" => " Refund "}, source: "/vendor")
{:ok, _same, [%Jido.Agent.Directive.Emit{signal: opened}]} =
  TransformGuide.WebhookAgent.cmd(adapter, created)

{"ticket.opened", %{subject: "Refund"}, "/vendor"} = {opened.type, opened.data, opened.source}
```

An `{:error, reason}` result fails the Turn. Execution wraps a reason that is not an exception in a `Jido.Error.ExecutionError`, and keeps the original in `details.reason`.

```elixir
empty = Jido.Signal.new!("webhook.ticket.created", %{}, source: "/vendor")

{:error, %Jido.Error.ExecutionError{details: %{reason: :missing_subject}}} =
  TransformGuide.WebhookAgent.cmd(adapter, empty)
```

### Use clauses

A body of `->` clauses takes no argument. Each clause matches the Signal and can use a guard.

```elixir
defmodule TransformGuide.PriorityAgent do
  use Jido.Agent, name: "priority_adapter"

  routes do
    route "ticket.raw" do
      transform do
        %Jido.Signal{data: %{level: level}} = signal when level >= 8 ->
          {:ok, %{signal | type: "ticket.urgent"}}

        %Jido.Signal{data: %{level: level}} = signal when level >= 0 ->
          {:ok, %{signal | type: "ticket.normal"}}
      end
    end
  end
end

priority = TransformGuide.PriorityAgent.instantiate!(id: "priority-1")
raw = fn data -> Jido.Signal.new!("ticket.raw", data, source: "/helpdesk") end

{:ok, _same, [%{signal: %{type: "ticket.urgent"}}]} =
  TransformGuide.PriorityAgent.cmd(priority, raw.(%{level: 9}))

{:error, %Jido.Error.ValidationError{code: :transform_input}} =
  TransformGuide.PriorityAgent.cmd(priority, raw.(%{level: -1}))
```

A Signal that no clause matches returns `:transform_input`. Any other return value fails with `:invalid_result`.

### Use a module function

In a Map definition, a transform target is `{module, function, 1}` and must name a public function. Inline `transform` bodies compile to this form.

```elixir
defmodule TransformGuide.Normalizer do
  def to_ticket(%Jido.Signal{} = signal), do: {:ok, %{signal | type: "ticket.opened"}}
end

{:ok, definition} =
  Jido.Agent.define(%{
    name: "normalizer",
    routes: [
      %{
        path: "webhook.opened",
        handler: %{kind: :transform, target: {TransformGuide.Normalizer, :to_ticket, 1}}
      }
    ]
  })

{:ok, _same, [%{signal: %{type: "ticket.opened"}}]} =
  definition
  |> Jido.Agent.instantiate!(id: "normalizer-1")
  |> Jido.Agent.cmd(Jido.Signal.new!("webhook.opened", %{}, source: "/vendor"))
```

## Where the output goes

A `Jido.Agent.cmd/3` call only returns the `Emit`. An AgentServer delivers it after commit and uses the first of these that applies:

1. Connections the Agent declares for that Signal type from `:root`.
2. The parent, when the Agent is a topology member. The parent's connections decide the recipients.
3. The AgentServer's `:default_dispatch` option.
4. The Agent's own AgentServer, as a new cast.

The last case means an Agent can receive its own output. Give the output a type that does not match the transform route, or the route runs again. See [Connect Agent Outputs](../composition/connect-agent-outputs.livemd).

## Limits of terminal routes

These route declarations fail:

- `:defaults`, because no Action or Flow takes input. The code is `:invalid_defaults`.
- `state`, including in a Map definition, unless it is `:unchanged`. The code is `:terminal_state`.
- `reply`. The code is `:terminal_reply`.

The `:as` option works, so a terminal route can have a Signal helper. A transform that needs to read Agent state or change it must be an Action route that returns an emit Directive. See [State and Directives](agent-results-and-directives.md).

## Related

- [Routes and Handlers](build-agent-routes.livemd) covers route selection.
- [Declare Agent Topology](../composition/declare-agent-topology.livemd) covers named members.
