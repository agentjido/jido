---
modules:
  - Jido.Plugin.Bus
  - Jido.Plugin.Bus.Client
  - Jido.Plugin.Bus.Client.Runtime
  - Jido.Plugin.Bus.Client.Server
  - Jido.Plugin.Bus.DSL
  - Jido.Plugin.Bus.DSL.References
  - Jido.Plugin.Bus.Manager
  - Jido.Plugin.Bus.Manager.Server
---

## Purpose

Protect the bundled Bus Plugin's local Bus declaration, owned Bus process, and
Agent subscription runtime. The component connects an Agent to a Signal Bus,
reconnects after replacement, delivers normal input, and acknowledges durable
input only after a successful Agent Turn.

The component does not own Signal Bus routing, storage, replay, cursor, or
subscription internals. It also does not own generic Plugin callback timing or
the work that a receiving Agent performs.

The public boundary is `Jido.Plugin.Bus.Manager`, `Jido.Plugin.Bus.Client`,
and `Jido.Plugin.Bus.DSL`. Their server and runtime modules are internal. The
`signal_bus` section owns local endpoint declaration. Manager and Client use
the standard Agent Plugin DSL and add no other DSL.

## Obligations

### jido.plugin.bus.I1 — Local Bus declaration

- **scope:** `Jido.Plugin.Bus.DSL`, `Jido.Plugin.Bus.DSL.References`
- **must:** Declare exactly one `signal_bus` section with a required atom name, provide direct data parity, expose its endpoint, construct stable Bus references, reject Bus-to-Bus connections, and require single delivery when a connection publishes to a Bus.
- **kind:** functional
- **status:** active

### jido.plugin.bus.I2 — Managed Bus ownership

- **scope:** `Jido.Plugin.Bus.Manager`, `Jido.Plugin.Bus.Manager.Server`
- **must:** Declare one permanent Signal Bus child, use the Agent ID and Jido instance as defaults, preserve explicit Bus options, and stop the Bus with its owning Agent.
- **kind:** functional
- **status:** active

### jido.plugin.bus.I3 — Client configuration and subscription

- **scope:** `Jido.Plugin.Bus.Client`, `Jido.Plugin.Bus.Client.Runtime`, `Jido.Plugin.Bus.Client.Server`
- **must:** Accept only the typed AgentServer-owned `bus`, `durable`, `jido`, `path`, `retry_delay_ms`, `start_from`, and `timeout` options. Apply Client defaults, reject invalid scope and durable replay positions before subscription, subscribe with the selected scope and durable options, and fail initial subscription when the selected Bus is absent. Keep Signal Bus path, cursor, and subscription validation in `jido_signal`.
- **kind:** functional
- **status:** active

### jido.plugin.bus.I4 — Readiness and reconnect

- **scope:** `Jido.Plugin.Bus.Client.Runtime`, `Jido.Plugin.Bus.Client.Server`
- **must:** Report readiness only for the registered Bus and active subscription, reconnect to a replacement Bus, keep stale reconnect work inert, and return a structured error when the runtime is unavailable.
- **kind:** functional
- **status:** active

### jido.plugin.bus.I5 — Normal Signal delivery

- **scope:** `Jido.Plugin.Bus.Client.Runtime`
- **must:** Cast each normal subscribed Signal to the owning AgentServer without adding durable acknowledgement behavior.
- **kind:** functional
- **status:** active

### jido.plugin.bus.I6 — Durable commit and acknowledgement order

- **scope:** `Jido.Plugin.Bus.Client.Runtime`
- **must:** Deliver one durable record through an AgentServer call, acknowledge it only after the Turn commits, and do not admit the next durable record before that acknowledgement.
- **kind:** ordering
- **status:** active

### jido.plugin.bus.I7 — Durable retry and reattachment

- **scope:** `Jido.Plugin.Bus.Client.Runtime`
- **must:** Retry a failed durable Turn or acknowledgement, keep stale retry work inert, and reattach the same durable subscription after runtime replacement.
- **kind:** functional
- **status:** active

### jido.plugin.bus.I8 — Delivery ownership and fault containment

- **scope:** `Jido.Plugin.Bus.Client.Runtime`
- **must:** Run a durable AgentServer call outside the Client mailbox, retry after delivery-worker failure, and stop a pending delivery worker when its Client runtime stops.
- **kind:** functional
- **status:** active
