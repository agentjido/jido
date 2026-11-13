---
title: Jido component
status: current
last-reviewed: 2026-11-13
---

# Jido component

Purpose: Define and supervise one Jido instance. Manage the logical and
resident life of Agents in that instance.

Review result: The component boundary is confirmed. `Jido` is the public
facade. `Jido.Instance` is an internal support namespace. `Jido.Application`
is the package composition root and is not a separate public component.

## Public contract

The public surface has four groups:

- `use Jido` declares one supervised instance. The generated module supplies
  `config/1`, `child_spec/1`, and `start_link/1`.
- `start/1`, `stop/1`, `start_link/1`, and `child_spec/1` control an instance.
- `start_agent/3`, `stop_agent/3`, `whereis_agent/3`, `list_agents/2`,
  `resident_agent_count/2`, and `thaw/4` control resident Agents by ID or PID.
- `agent_address/3`, `resolve_agent/2`, `create_agent/4`, `activate_agent/3`,
  `reconcile_agent/3`, `upgrade_agent/4`, `call/4`, `cast/3`, `submit/4`,
  `delete_agent/3`, `cancel_turn/4`, and `status/3` control logical Agents by a
  stable `Jido.Agent.Address`.

The resident API is a direct runtime convenience. The Address API is the stable
logical identity and durable activation boundary. A Address operation resolves the
current activation again. It does not keep a worker PID.

## OTP boundary

One Jido instance is one named Supervisor. It owns these instance-scoped
children:

- a Runic Runner;
- a Task Supervisor;
- the Agent registration guard and Registry;
- the internal runtime store;
- the durable wake worker;
- the dynamic Agent activation supervisor.

The package `Jido.Application` owns shared package services. These include the
Signal Registry, global Exec Task Supervisor, Catalog discovery, AI correlation
store, namespace registry, ETS persistence owner, and default Runic Runner.

The internal `Jido.Instance` namespace owns names, option validation, namespace
claims, runtime defaults, and durable wake timers. None of these modules is a
second public instance facade.

## API use

Tests, examples, and guides use both public lifecycle forms. Direct examples
usually use `start_agent/3` and a worker PID. Durable and recovery paths use a
stable Address. AgentServer, Persistence, Exec, Telemetry, and Plugin runtime code
consume the internal instance names and defaults.

The current Covenant owner is `jido.instance`. It covers instance declaration,
supervision, namespaces, fixed defaults, resident lifecycle selection, Address
construction, Address resolution, Address routing, and durable create and activation.

## Duplication and reduction review

The two lifecycle forms have different uses, but the boundary is not clear in
all guides. `thaw/4` restores by module and ID. The newer Address API restores by
stable logical identity. Keep both only while the compatibility use is
explicit. New durable documentation should use the Address API.

`Jido.Instance.Names`, `Options`, `NamespaceRegistry`, `RuntimeStore`, and
`Wake` have separate internal responsibilities. A new public Instance module
would duplicate the `Jido` facade and is not needed.

## Elixir and OTP design

The component uses a normal Supervisor for fixed instance services and a
DynamicSupervisor for Agent activations. Stable names derive from the instance
module. A global namespace registry monitors the owner process and releases a
binding after owner loss. Startup waits for old named children to stop before
it reuses their names.

This ownership model is suitable for OTP. The public module is large, but its
large size comes from one lifecycle facade and not from a second process
abstraction. Private functions hold the activation, validation, and routing
details.

## Open findings

### J1 — Removed count API remains in contracts and guides

Nine guide or contract files call `Jido.agent_count/2`. The current public
function is `Jido.resident_agent_count/2`. These examples fail if they run.
The `jido.instance.I5` obligation also names the removed function.

### J2 — Removed hibernate API remains in guides

Eight guide or support files call `Jido.hibernate/2`. The current `Jido`
module has no such function. The affected guidance must use the current
passivation or stop contract.

### J3 — Old activate-or-create examples conflict with strict activation

Six guide files use `Jido.activate_agent(instance, address, AgentModule)`. The
current third argument is an option list. Current activation strictly restores
an existing durable record. It does not create a missing Agent. The old examples
therefore conflict with both the function shape and the durable identity rule.

### J4 — One retained decision record is stale

The instance decision record says that a generated instance has `namespace/0`.
The generated module does not export that function, and the tests confirm its
absence. The decision text must match the supported generated API.

## Proof

The 2026-11-13 focused command ran the instance, Plugin, AI, and malformed
public-input suites together. It passed 502 tests. This record also traced the
Jido facade, Application composition, Instance services, Covenant obligations,
callers, examples, and guides.

The focused command did not execute every guide or Livebook. Findings J1
through J3 came from static caller tracing. No production fix was part of this
review.

## Sources

- [Jido facade](../../lib/jido.ex)
- [Application composition](../../lib/jido/application.ex)
- [Instance options](../../lib/jido/instance/options.ex)
- [Namespace registry](../../lib/jido/instance/namespace_registry.ex)
- [Runtime store](../../lib/jido/instance/runtime_store.ex)
- [Wake worker](../../lib/jido/instance/wake.ex)
- [Instance obligations](../../test/contracts/jido/instance.obligations.md)
