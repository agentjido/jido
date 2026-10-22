---
modules:
  - Jido.Plugin.Heartbeat
  - Jido.Plugin.Heartbeat.Runtime
  - Jido.Plugin.Heartbeat.Signal.Tick
---

## Purpose

Protect the bundled Heartbeat Plugin's timer configuration and periodic Signal
production. The component validates timer options, declares one supervised
runtime child, and sends a fresh Signal for each timer event.

The component does not own generic Plugin normalization, AgentServer mailbox
processing, Agent evaluation, or the work that a receiving Agent performs.

The public boundary is `Jido.Plugin.Heartbeat` and its default
`Jido.Plugin.Heartbeat.Signal.Tick` definition. The timer runtime and the
configuration helper are internal. Heartbeat uses the standard Agent Plugin
configuration and adds no custom DSL section.

## Obligations

### jido.plugin.heartbeat.I1 — Plugin and timer configuration

- **scope:** `Jido.Plugin.Heartbeat`, `Jido.Plugin.Heartbeat.configuration/1`
- **must:** Own exactly the AgentServer options `interval`, `signal_type`, `signal_data`, and `source`, add no custom DSL section, apply the documented defaults, and accept a positive interval, a non-empty valid UTF-8 Signal type, plain map data, and a non-empty valid URI-reference source.
- **kind:** functional
- **status:** active

### jido.plugin.heartbeat.I2 — Configuration rejection

- **scope:** `Jido.Plugin.Heartbeat.configuration/1`, `Jido.Plugin.Heartbeat.validate_options/1`, `Jido.Plugin.Heartbeat.Runtime.start_link/1`
- **must:** Reject unknown and duplicate options at Plugin normalization. Reject an invalid owned value with its structured Heartbeat reason before the runtime starts, and expose Plugin validation failures as a validation error.
- **kind:** functional
- **status:** active

### jido.plugin.heartbeat.I3 — One runtime child

- **scope:** `Jido.Plugin.Heartbeat.child_spec/1`, `Jido.Plugin.Heartbeat.Runtime.start_link/1`
- **must:** Keep the runtime internal, declare one Heartbeat runtime child for the supplied Plugin Init value, and link the started runtime to its owner.
- **kind:** functional
- **status:** active

### jido.plugin.heartbeat.I4 — Fresh default ticks

- **scope:** `Jido.Plugin.Heartbeat.Runtime.handle_info/2`, `Jido.Plugin.Heartbeat.Signal.Tick`
- **must:** Expose the default Tick Signal definition. On each timer event, cast one fresh Tick with the configured data and source, and schedule the next timer event.
- **kind:** functional
- **status:** active

### jido.plugin.heartbeat.I5 — Fresh custom ticks

- **scope:** `Jido.Plugin.Heartbeat.Runtime.handle_info/2`
- **must:** When a custom Signal type is configured, cast one fresh generic Signal with that type, the configured data and source, and schedule the next timer event.
- **kind:** functional
- **status:** active
