# Use Jido Signal

Jido uses [Jido Signal](https://hexdocs.pm/jido_signal/) for typed messages,
routing, dispatch, trace context, and local Bus delivery.

## Use Signals As Actor Messages

An Agent route selects executable work from `signal.type`. Signal data becomes
the route input after defaults are applied. Signal context attributes keep
message identity, source, subject, time, and trace data outside domain payload.

```elixir
signal =
  Jido.Signal.new!(
    "orders.approve",
    %{order_id: "order-7"},
    source: "/checkout",
    subject: "order-7"
  )
```

Use a stable type and source. Do not use a new Signal ID as the only business
idempotency key.

## Choose Direct Or Routed Delivery

Use `Jido.AgentServer.call/3` when a producer has one actor reference and needs
the commit result. Use `cast/2` when best-effort input is enough.

Use a Signal Bus when producers and consumers should be connected through
paths instead of direct process references. Use Jido Signal Dispatch when a
post-commit effect must reach a PID, Bus, PubSub topic, HTTP endpoint, or log
adapter.

## Keep Delivery Guarantees Explicit

Normal Bus subscriptions are live local delivery. Durable subscriptions retain
one cursor and use at-least-once ordered delivery. The included memory Store
does not survive Bus or VM restart.

Dispatch is not a durable outbox. A timeout can be indeterminate. Receivers
must handle duplicates when a sender can retry.

## Preserve Trace Context

Jido propagates Signal causation and trace data through supported outbound
dispatch. Keep business correlation IDs in explicit Signal data or extension
attributes when they must cross system boundaries.

## Keep The Package Boundary Clear

Jido Signal owns the message envelope and delivery tools. Core Jido owns Agent
state, serial Turns, commit rules, Plugin lifecycle, and actor relationships.
Read the Jido Signal guides for the complete CloudEvents, Router, Bus, and
adapter contracts.

Continue with [Connect A Signal Bus](signal-buses.livemd) and
[Dispatch Signals](signal-dispatch.livemd).
