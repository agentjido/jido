---
modules:
  - Jido.Plugin.SensorManager
  - Jido.Plugin.SensorManager.Agent
  - Jido.Plugin.SensorManager.Init
  - Jido.Plugin.SensorManager.Runtime
  - Jido.Plugin.SensorManager.Runtime.Controller
  - Jido.Plugin.SensorManager.Server
  - Jido.Plugin.SensorManager.Start
  - Jido.Plugin.SensorManager.Stop
---

## Purpose

Protect the bundled SensorManager Plugin's portable desired state and its live
sensor reconciliation. The component validates desired sensor Directives,
reduces them in order, supervises the desired processes, retries failed work,
and fences stale reconciliation work.

The component does not own a sensor module's behavior, generic Plugin callback
timing, AgentServer commit atomicity, or Signal processing by the receiving
Agent.

The public boundary is `Jido.Plugin.SensorManager`, its `Start` and `Stop`
Directives, and the sensor-facing `Init` value. Agent state, runtime,
controller, and server modules are internal. Sensor Manager uses the standard
Plugin configuration and adds no custom DSL section.

## Obligations

### jido.plugin.sensor_manager.I1 — Portable sensor Directives

- **scope:** `Jido.Plugin.SensorManager.start/3`, `Jido.Plugin.SensorManager.stop/1`, `Jido.Plugin.SensorManager.Start.validate/1`, `Jido.Plugin.SensorManager.Stop.validate/1`
- **must:** Expose typed Start and Stop constructors and validation. Accept only a non-nil portable tag, a loaded sensor module with `child_spec/1`, and portable map configuration. Expose no other documented Sensor Manager functions.
- **kind:** functional
- **status:** active

### jido.plugin.sensor_manager.I2 — Ordered desired state

- **scope:** `Jido.Plugin.SensorManager.Agent.state_spec/1`, `Jido.Plugin.SensorManager.Agent.directives/1`, `Jido.Plugin.SensorManager.Agent.reduce/2`
- **must:** Own one `:sensors` field with an empty desired map, declare only Start and Stop, apply those Directives in order, and ignore other Directive types.
- **kind:** ordering
- **status:** active

### jido.plugin.sensor_manager.I3 — Runtime configuration and sensor input

- **scope:** `Jido.Plugin.SensorManager`, `Jido.Plugin.SensorManager.Server`, `Jido.Plugin.SensorManager.Init`
- **must:** Own exactly the AgentServer option `retry_delay_ms`, add no custom DSL section, reject unknown or duplicate Plugin options, and accept only a delay from 1 through 4,294,967,295 milliseconds. Declare one permanent Sensor Manager runtime child and expose the typed Init value given to each sensor.
- **kind:** functional
- **status:** active

### jido.plugin.sensor_manager.I4 — Exact reconciliation

- **scope:** `Jido.Plugin.SensorManager.Runtime.reconcile/4`, `Jido.Plugin.SensorManager.Runtime.sensors/1`
- **must:** Reuse a live sensor only when its module and configuration are exactly unchanged, replace only changed sensors, start missing desired sensors, and stop sensors that are no longer desired.
- **kind:** functional
- **status:** active

### jido.plugin.sensor_manager.I5 — Monotonic revision fence

- **scope:** `Jido.Plugin.SensorManager.Runtime.Controller`
- **must:** Record the restored revision, accept only reconciliation work newer than the last successful revision, and ignore an old retry token after newer work succeeds.
- **kind:** ordering
- **status:** active

### jido.plugin.sensor_manager.I6 — Supervision recovery

- **scope:** `Jido.Plugin.SensorManager.Runtime`, `Jido.Plugin.SensorManager.Runtime.Controller`
- **must:** Restart a failed sensor while its tag remains desired and restore the desired sensor set when an internal runtime child restarts.
- **kind:** functional
- **status:** active

### jido.plugin.sensor_manager.I7 — Bounded retry ownership

- **scope:** `Jido.Plugin.SensorManager.Runtime.Controller`
- **must:** Retry a failed start or restart after the configured delay, keep only one current retry timer, and cancel retry ownership when later reconciliation succeeds.
- **kind:** functional
- **status:** active

### jido.plugin.sensor_manager.I8 — Runtime fault containment

- **scope:** `Jido.Plugin.SensorManager.Runtime.Controller`, `Jido.Plugin.SensorManager.Server.dispatch/4`, `Jido.Plugin.SensorManager.Server.await_ready/2`
- **must:** Return structured failures for invalid child specifications, failed child starts, ignored children, and an unavailable runtime without changing the desired state contract.
- **kind:** functional
- **status:** active
