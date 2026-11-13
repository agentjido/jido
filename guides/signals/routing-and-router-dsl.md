# Signal Routing

Map Signal types to targets with exact paths and wildcards, and predict the order of the results. `Jido.Signal.Router` is an immutable lookup value. It returns the targets that match a Signal and never runs them, so a target can be any term.

To route Signals to Agent behavior, start with [Routes and Handlers](../agents/build-agent-routes.livemd). This guide covers the routing rules underneath.

## Build a Router and route a Signal

```elixir
alias Jido.Signal
alias Jido.Signal.Router

router =
  Router.new!([
    {"order.placed", :reserve_stock},
    {"order.*", :record_order_event},
    {"audit.**", :write_audit_log}
  ])

placed = Signal.new!("order.placed", %{}, source: "/shop")

{:ok, [:reserve_stock, :record_order_event]} = Router.route(router, placed)

shipped = Signal.new!("order.shipped", %{}, source: "/shop")
{:ok, [:record_order_event]} = Router.route(router, shipped)

{:error, %Jido.Error.RoutingError{} = error} =
  Router.route(router, Signal.new!("invoice.paid", %{}, source: "/billing"))

:no_handlers_found = error.details.reason
```

No match is an error from `Jido.Signal.Router.route/2`. All matching targets are returned, not only the first one.

## Path patterns

A path is a list of segments separated by dots. A segment contains letters, digits, `_`, or `-`, or it is a whole wildcard.

| Pattern part | Matches | Example |
| --- | --- | --- |
| `order.placed` | That exact type. | Matches `order.placed` only. |
| `*` | Exactly one segment. | `order.*` matches `order.placed`, not `order.item.added`. |
| `**` | Zero or more segments. | `audit.**` matches `audit` and `audit.user.created`. |

`Jido.Signal.Router.matches?/2` tests one type against one pattern.

```elixir
alias Jido.Signal.Router

true = Router.matches?("order.placed", "order.*")
false = Router.matches?("order.item.added", "order.*")
true = Router.matches?("order.item.added", "order.**")
true = Router.matches?("order", "order.**")
true = Router.matches?("order.created", "order.**.created")
true = Router.matches?("order.eu.created", "order.*.created")
```

These paths are rejected. A wildcard must fill its whole segment.

```elixir
alias Jido.Signal.Router

{:error, %{message: "Path cannot contain consecutive dots"}} = Router.new({"order..placed", :target})
{:error, %{message: "Path cannot contain '*' within a segment"}} = Router.new({"order.pl*", :target})
{:error, %{message: "Path cannot contain '**' sequence"}} = Router.new({"order.**x", :target})
{:error, %{message: "Path cannot contain multiple wildcards"}} = Router.new({"order.**.**", :target})
{:error, %{message: "Path contains invalid characters"}} = Router.new({"order placed", :target})
```

A path can also be a module defined with `use Jido.Signal`. See [Custom Signals](signals-and-custom-types.md).

## Route specifications

`Jido.Signal.Router.new/2` and `Jido.Signal.Router.add/2` accept one specification or a list. `Jido.Signal.Router.new!/2` raises `Jido.Error.ValidationError` for a bad one.

| Form | Meaning |
| --- | --- |
| `{path, target}` | Priority 0, no predicate. |
| `{path, target, priority}` | An integer from -100 to 100. |
| `{path, match, target}` | Adds a predicate. |
| `{path, match, target, priority}` | Adds both. |
| `%Jido.Signal.Router.Route{}` | The struct form. |

A target that is a list contributes each of its items to the result.

```elixir
alias Jido.Signal
alias Jido.Signal.Router

router = Router.new!({"order.placed", [:reserve_stock, :send_receipt]})
signal = Signal.new!("order.placed", %{}, source: "/shop")

{:ok, [:reserve_stock, :send_receipt]} = Router.route(router, signal)
```

## Result order

Matching targets are sorted by these rules, in order:

1. Exact paths come before paths with `*`, and those come before paths with `**`.
2. Within a class, the more specific pattern comes first. Literal segments score higher, especially early ones.
3. For equal specificity, the higher `priority` comes first.
4. For equal priority, the earlier registration comes first.

Priority cannot lift a wildcard route above an exact route, and cannot lift a less specific pattern above a more specific one.

```elixir
alias Jido.Signal
alias Jido.Signal.Router

signal = Signal.new!("order.placed", %{}, source: "/shop")

router =
  Router.new!([
    {"order.**", :multi, 100},
    {"order.*", :single, 100},
    {"order.placed", :exact, -100}
  ])

{:ok, [:exact, :single, :multi]} = Router.route(router, signal)

router =
  Router.new!([
    {"*.placed", :less_specific, 100},
    {"order.*", :more_specific, -100}
  ])

{:ok, [:more_specific, :less_specific]} = Router.route(router, signal)

router =
  Router.new!([
    {"order.placed", :first_registered},
    {"order.placed", :higher_priority, 50},
    {"order.placed", :second_registered}
  ])

{:ok, [:higher_priority, :first_registered, :second_registered]} = Router.route(router, signal)
```

## Add a predicate

A predicate inspects the whole Signal. It runs only after the path matches. A runtime Router accepts a one-argument function or a `{module, function, args}` value. The Signal is the first argument, followed by `args`.

The route matches only when the predicate returns exactly `true`. Any other value counts as no match, and so does a predicate that raises, throws, or exits.

```elixir
defmodule GuideRouting.OrderRules do
  def over_limit?(signal, limit_cents), do: signal.data["total_cents"] > limit_cents
end

alias Jido.Signal
alias Jido.Signal.Router

router =
  Router.new!([
    {"order.placed", :record_order},
    {"order.placed", {GuideRouting.OrderRules, :over_limit?, [50_000]}, :request_review},
    {"order.placed", fn signal -> signal.subject == "vip" end, :notify_account_manager}
  ])

large = Signal.new!("order.placed", %{"total_cents" => 90_000}, source: "/shop")
{:ok, [:record_order, :request_review]} = Router.route(router, large)

small = Signal.new!("order.placed", %{"total_cents" => 900}, source: "/shop", subject: "vip")
{:ok, [:record_order, :notify_account_manager]} = Router.route(router, small)
```

A predicate failure is not reported, so a broken predicate looks like a non-matching route.

## Define a Router module

`use Jido.Signal.Router` compiles the same specifications into a module with `router/0`, `routes/0`, and `route/1`. Use it for a fixed route table.

Predicates in this form must be `{module, function, args}` values. An anonymous function, PID, port, or reference raises `CompileError`.

```elixir
defmodule GuideRouting.OrderPlaced do
  use Jido.Signal, type: "order.placed", default_source: "/shop"
end

defmodule GuideRouting.OrderRouter do
  use Jido.Signal.Router

  route GuideRouting.OrderPlaced, :reserve_stock
  route "order.*", :record_order_event
  route "audit.**", :write_audit_log, -50
  route "order.placed", {GuideRouting.OrderRules, :over_limit?, [50_000]}, :request_review
  route "order.placed", {GuideRouting.OrderRules, :over_limit?, [90_000]}, :escalate, 10
end

signal = GuideRouting.OrderPlaced.new!(%{"total_cents" => 100_000})

{:ok, [:escalate, :reserve_stock, :request_review, :record_order_event]} =
  GuideRouting.OrderRouter.route(signal)

5 = length(GuideRouting.OrderRouter.routes())
```

`route` takes the same forms as the table above, without the outer tuple.

## Change and inspect a Router

A Router is a value, so each change returns a new Router.

```elixir
alias Jido.Signal
alias Jido.Signal.Router

{:ok, router} = Router.new({"order.placed", :reserve_stock})
{:ok, router} = Router.add(router, [{"order.*", :record_order_event}, {"order.placed", :send_receipt}])
{:ok, router} = Router.merge(router, Router.new!({"audit.**", :write_audit_log}))

4 = Router.count(router)
false = Router.empty?(router)
true = Router.has_route?(router, "order.*")
false = Router.has_route?(router, "order.shipped")

{:ok, routes} = Router.list(router)
["order.placed", "order.*", "order.placed", "audit.**"] = Enum.map(routes, & &1.path)

{:ok, router} = Router.remove(router, "order.placed")
2 = Router.count(router)

placed = Signal.new!("order.placed", %{}, source: "/shop")
paid = Signal.new!("invoice.paid", %{}, source: "/billing")
[^placed] = Router.filter([placed, paid], "order.*")
```

- `Jido.Signal.Router.has_route?/2` compares registered path text. It does not test whether a type would match.
- `Jido.Signal.Router.remove/2` removes all routes with that path.
- `Jido.Signal.Router.list/1` returns routes in registration order, not match order.
- `Jido.Signal.Router.filter/2` selects Signals by pattern with no Router involved.

## Related

- Transforms and Forwards for Agent route behavior.
- [Signal Bus](signal-bus-and-subscriptions.md), which uses these path rules for subscriptions.
- [Signal Dispatch Adapters](dispatch-adapters.md) to deliver a Signal to a target. A dispatch target can be a Router target, but the Router does not deliver it.
