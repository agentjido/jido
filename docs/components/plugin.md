---
title: Jido.Plugin component
status: current
last-reviewed: 2026-11-13
---

# Jido.Plugin component

Purpose: Define one reusable Plugin contract and ship five standard Plugin
capabilities.

Review result: The parent component and all five bundled sub-components are
confirmed. No production defect was found in this review.

## Parent public contract

`use Jido.Plugin` defines one Plugin module. A Plugin can implement optional
callbacks for three owners:

- Agent callbacks prepare input, select a route, declare owned state and
  Directives, and reduce that state.
- AgentServer callbacks validate runtime options, admit Signals, prepare
  outbound Signals, dispatch Directives, supervise a runtime, wait for runtime
  readiness, and run work after commit.
- Persistence callbacks dump and load the one owned state value.

`Jido.Plugin.Input`, `Init`, `Context`, and the Admission, Commit, and
Persistence context values are public handoff data. Manifest, Normalizer, Spec,
and callback error helpers are internal.

Plugin normalization converts declarations into one ordered and validated
Spec list. Agent, AgentServer, and Persistence then consume only their owned
part of each Spec.

## API use

Agent definition and evaluation use the Agent callbacks. AgentServer hosts
Plugin runtimes and owns callback order. Persistence converts Plugin-owned
state. The five bundled Plugins use the same public declaration contract as an
application Plugin.

The generic `jido.plugin` Covenant owner tests declaration identity, callback
discovery, option isolation, normalization, state and Directive ownership,
fault containment, and public context values.

## Duplication and reduction review

The optional callback list is broad, but the three owner groups keep one
Plugin declaration and one set of options. Separate public facet behaviors
would add more declarations and duplicate identity. The current single-module
contract is retained.

The bundled capabilities do not duplicate the generic Plugin contract. Each
one owns domain behavior and uses the generic callbacks.

## Elixir and OTP design

Compile-time callback discovery creates a static Manifest. Runtime consumers
do not inspect arbitrary function names. Callback invocation contains raises,
throws, and exits and returns a Plugin-scoped error.

Plugin processes stay under the Agent activation root. Each Plugin that needs
live state supplies a normal child specification. The AgentServer owns startup,
readiness, restart, commit order, and shutdown.

## Audit sub-component

`Jido.Plugin.Audit` creates portable Audit records and reduces them into one
bounded `:audit` field. It has no process. Record order and `max_entries` are
part of its public contract.

Result: Retain it as one pure sub-component. It does not overlap Telemetry,
because Audit records are committed domain state.

## Bus sub-component

The Bus capability has three public entries:

- `Jido.Plugin.Bus.Manager` owns one local `Jido.Signal.Bus` process.
- `Jido.Plugin.Bus.Client` subscribes an Agent to a Bus.
- `Jido.Plugin.Bus.DSL` adds static Bus endpoints to Agent authoring.

Manager and Client are separate Plugin packages, but they form one integration
capability. Manager can host a Bus without a Client. Client can connect to a
Bus that another owner hosts. The shared Covenant owner covers local ownership,
subscription, reconnect, delivery, durable acknowledgement, and retry.

Result: Keep one checklist sub-component with the three explicit public entry
modules. Do not add an empty `Jido.Plugin.Bus` facade.

## Heartbeat sub-component

`Jido.Plugin.Heartbeat` validates one periodic timer and sends a fresh Signal
for each tick. Its runtime owns only the next timer. The default Tick Signal is
public.

Result: Retain it as the small periodic-input capability. It does not replace
Scheduler because it has no portable schedule state, cron rule, or occurrence
identity.

## Scheduler sub-component

`Jido.Plugin.Scheduler` owns delayed and recurring Signal definitions. Public
Schedule, Cron, and Cancel Directives control it. Occurrence data gives a
stable identity to a generated tick. A DeliveryAdapter can move delivery to an
external system.

The runtime reconciles committed recurring state, fences old revisions, tracks
one-shot timers outside Agent state, retries failed reconciliation, and restores
future jobs after replacement.

Result: Retain it as one scheduling sub-component. Durable business delivery,
acknowledgement, and queue storage stay outside it.

## Sensor Manager sub-component

`Jido.Plugin.SensorManager` owns a portable desired sensor map. Start and Stop
Directives update that map. A Supervisor and controller reconcile live sensor
children to the committed value. Revision fencing and one retry timer prevent
old work from replacing new work.

Result: Retain it as one supervised-input sub-component. Sensor behavior and
Signal handling stay with the sensor and Agent.

## Proof

The 2026-11-13 focused command ran the complete `test/jido/plugin` tree as part
of a 502-test command. All tests passed. The review also traced the generic
Plugin Covenant owner and the focused Audit, Bus, Heartbeat, Scheduler, and
Sensor Manager Covenant owners.

The review did not run real external Bus or Scheduler adapters. It made no
production change.

## Sources

- [Plugin behavior](../../lib/jido/plugin.ex)
- [Plugin normalizer](../../lib/jido/plugin/normalizer.ex)
- [Audit](../../lib/jido/plugin/audit.ex)
- [Bus Manager](../../lib/jido/plugin/bus/manager.ex)
- [Bus Client](../../lib/jido/plugin/bus/client.ex)
- [Heartbeat](../../lib/jido/plugin/heartbeat.ex)
- [Scheduler](../../lib/jido/plugin/scheduler.ex)
- [Sensor Manager](../../lib/jido/plugin/sensor_manager.ex)
- [Plugin obligations](../../test/contracts/jido/plugin.obligations.md)
