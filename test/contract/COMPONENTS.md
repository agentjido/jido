# Covenant component register

Status: Approved map; all components active; final hardening in progress

This register defines the approved Covenant component boundaries for Jido V3.
All component IDs start with `jido.`. Durable behavior stays under the
`jido.agent_server` boundary.

A planned row is not an active Covenant component. A component becomes active
only when it has an `*.obligations.md` file and passing tests with its
obligation tags. Do not add mutation profiles or obligation files as part of
this scaffold.

## Current active components

| Component | State | Current contract area |
| --- | --- | --- |
| `jido.instance` | Active | `test/contract/jido.instance/` |
| `jido.plugin` | Active | `test/contract/jido.plugin/core/` |
| `jido.plugin.audit` | Active | `test/contract/jido.plugin/audit/` |
| `jido.plugin.bus` | Active | `test/contract/jido.plugin/bus/` |
| `jido.plugin.heartbeat` | Active | `test/contract/jido.plugin/heartbeat/` |
| `jido.plugin.scheduler` | Active | `test/contract/jido.plugin/scheduler/` |
| `jido.plugin.sensor_manager` | Active | `test/contract/jido.plugin/sensor_manager/` |
| `jido.agent` | Active | `test/contract/jido.agent/` |
| `jido.agent_evaluation` | Active | `test/contract/jido.agent_evaluation/` |
| `jido.signal_action` | Active | `test/contract/jido.signal_action/` |
| `jido.discovery` | Active | `test/contract/jido.discovery/` |
| `jido.telemetry` | Active | `test/contract/jido.telemetry/` |
| `jido.error` | Active | `test/contract/jido.error/` |
| `jido.persistence` | Active | `test/contract/jido.persistence/` |
| `jido.agent_server` | Active | `test/contract/jido.agent_server/core/` |
| `jido.agent_server.activation` | Active | `test/contract/jido.agent_server/activation/` |
| `jido.agent_server.effects` | Active | `test/contract/jido.agent_server/effects/` |
| `jido.agent_server.plugin_runtime` | Active | `test/contract/jido.agent_server/plugin_runtime/` |
| `jido.agent_server.composition` | Active | `test/contract/jido.agent_server/composition/` |
| `jido.agent_server.durable` | Active | `test/contract/jido.agent_server/durable/` |
| `jido.agent_server.durable_turn` | Active | `test/contract/jido.agent_server/durable_turn/` |

## Approved final components

| Component | State | Purpose | Planned contract area |
| --- | --- | --- | --- |
| `jido.instance` | Active | Jido instance supervision, namespace, options, and Ref routing | `test/contract/jido.instance/` |
| `jido.agent` | Active, to refine | Agent model, authoring, validation, logical topology, and edits | `test/contract/jido.agent/` |
| `jido.agent_evaluation` | Active | Pure Agent evaluation and candidate production | `test/contract/jido.agent_evaluation/` |
| `jido.agent_server` | Active | Core transient serialized Turn worker | `test/contract/jido.agent_server/core/` |
| `jido.agent_server.activation` | Active | Activation root, readiness, identity, and local recovery | `test/contract/jido.agent_server/activation/` |
| `jido.agent_server.effects` | Active | Ordered post-commit effects | `test/contract/jido.agent_server/effects/` |
| `jido.agent_server.plugin_runtime` | Active | Live generic Plugin hosting | `test/contract/jido.agent_server/plugin_runtime/` |
| `jido.agent_server.composition` | Active | Runtime child and connection resources | `test/contract/jido.agent_server/composition/` |
| `jido.agent_server.durable` | Active | Persistence-backed AgentServer state coordination | `test/contract/jido.agent_server/durable/` |
| `jido.agent_server.durable_turn` | Active | Durable Flow progress, waits, and receipts | `test/contract/jido.agent_server/durable_turn/` |
| `jido.persistence` | Active | Records, snapshots, adapters, storage operations, and revisions | `test/contract/jido.persistence/` |
| `jido.plugin` | Active | Generic Plugin SDK and callback contracts | `test/contract/jido.plugin/core/` |
| `jido.signal_action` | Active | Jido integration values for Signals and Actions | `test/contract/jido.signal_action/` |
| `jido.discovery` | Active | Read-only Action discovery | `test/contract/jido.discovery/` |
| `jido.telemetry` | Active | Telemetry, metrics, tracing, logs, and Debug support | `test/contract/jido.telemetry/` |
| `jido.error` | Active | Shared error taxonomy and stable common codes | `test/contract/jido.error/` |
| `jido.plugin.audit` | Active | Bundled Audit Plugin behavior | `test/contract/jido.plugin/audit/` |
| `jido.plugin.bus` | Active | Bundled Bus Plugin behavior | `test/contract/jido.plugin/bus/` |
| `jido.plugin.heartbeat` | Active | Bundled Heartbeat Plugin behavior | `test/contract/jido.plugin/heartbeat/` |
| `jido.plugin.scheduler` | Active | Bundled Scheduler Plugin behavior | `test/contract/jido.plugin/scheduler/` |
| `jido.plugin.sensor_manager` | Active | Bundled SensorManager Plugin behavior | `test/contract/jido.plugin/sensor_manager/` |

## Dependency rules

- `jido.agent_server` uses `jido.agent_evaluation` and its AgentServer
  subcomponents.
- `jido.agent_server.activation` uses `jido.instance`.
- `jido.agent_server.durable` and `jido.agent_server.durable_turn` use
  `jido.persistence`.
- Each `jido.plugin.*` bundled component uses `jido.plugin`.
- `jido.agent_evaluation` uses `jido.agent` and `jido.plugin`.
- `jido.telemetry` is best effort. An observation failure must not change
  consumer behavior.
- `jido_action` and `jido_signal` own their execution, routing, and transport
  internals. Jido Covenant components do not claim those rules.

## Activation rules

For each planned component:

1. Define its obligations from supported behavior.
2. Move or split existing tagged tests. Do not copy complete suites.
3. Select behavior-bearing mutation targets with no unexplained overlap.
4. Activate the new component and retire the replaced obligation in the same
   change.
5. Keep production code line count neutral or lower during extraction.

See
[`docs/covenant-component-refactor-plan.md`](../../docs/covenant-component-refactor-plan.md)
for the approved refactor sequence.
