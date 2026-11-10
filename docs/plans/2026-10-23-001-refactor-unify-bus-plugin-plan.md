---
title: "refactor: Unify the Bus plugin"
type: refactor
date: 2026-10-23
artifact_contract: ce-unified-plan/v1
artifact_readiness: requirements-only
product_contract_source: ce-plan-bootstrap
execution: code
target_repo: jido
deepened: 2026-10-23
---

# Refactor: Unify the Bus Plugin

## Goal Capsule

- **Objective:** Replace the split Bus Manager, Client, DSL, and private topology bridge with one packaged `Jido.Plugin.Bus` that uses exactly one Bus.
- **Authoring rule:** Bus input is declared with `connections`. Bus output is declared with `forward "signal.type", to: bus(:name)`.
- **Compatibility rule:** Delete the old public modules and data shapes. Do not add adapters or warnings.
- **Current state:** The public surface is clear. Four runtime and identity decisions still block an implementation-ready plan.
- **Target repo:** `jido`. Keep `jido_signal` unchanged unless later implementation proves that a required low-level operation is missing.
- **Execution rule:** Do not run this plan with `ce-work` yet. Resolve OQ1 through OQ4, then add final implementation units and verification commands.

---

## Product Contract

### Summary

An Agent selects `Jido.Plugin.Bus` once and declares exactly one Bus.
It can declare zero or more inbound Bus relationships in the existing `connections` section.
It can publish through a normal forward route.

The intended surface has no independent `subscribe` declaration:

```elixir
use Jido.Agent,
  name: "ledger",
  extensions: [Jido.Plugin.Bus]

signal_bus do
  name :orders
  ownership :managed
  options [max_log_size: 10_000]
end

topology do
  connections do
    connect "order.**",
      from: bus(:orders),
      to: :root,
      options: [
        durable: "ledger-orders",
        start_from: :origin
      ]
  end
end

routes do
  forward "audit.recorded", to: bus(:orders)
end
```

The connection path is the low-level Bus subscription path.
The connection `options` value holds Bus-specific subscription settings.
The core `delivery` field keeps its existing destination fan-out meaning.
It does not mean durable delivery.

### Problem Frame

The current design has four separate paths:

- `Jido.Plugin.Bus.Manager` starts one Bus.
- `Jido.Plugin.Bus.Client` subscribes one Agent to one path.
- `Jido.Plugin.Bus.DSL` declares one Bus topology endpoint.
- `Jido.AgentServer.TopologyBus` starts another private Bus and subscribes to `"**"`.

The private bridge receives every Signal and applies the declared connection path later.
The connection and the low-level subscription describe the same relationship twice.
The separate Client also cannot represent several inbound paths because an Agent can select one instance of a Plugin module.

### Actors

- A1. An Agent author declares one Bus, inbound connections, and outbound forward routes.
- A2. Agent authoring normalizes, validates, encodes, and decodes the portable definition.
- A3. AgentServer commits Turns and runs post-commit effects.
- A4. The Bus integration starts or resolves one Bus, attaches inbound paths, and publishes forwarded Signals.
- A5. A future Plugin author can add a forward target kind without replacing core Agent or parent targets.

### Requirements

**Public Bus boundary**

- R1. `Jido.Plugin.Bus` is the only public packaged Agent Bus plugin, and one selection declares exactly one Bus.
- R2. The Bus has one logical name, `:managed` or `:external` ownership, a portable scope, and static options.
- R3. A Bus-source connection is the only Agent authoring form for an inbound Bus subscription. The integration creates no hidden `"**"` subscription.
- R4. The declared Bus is a valid outbound target even when no inbound connection uses it.

**Extensible forwarding**

- R5. Core accepts Plugin-owned forward target kinds through a trusted Agent Extension contract for normalization, validation, document codecs, and safe views.
- R6. Core owns and reserves `:agent` and `:parent`. A Plugin can extend target kinds but cannot replace core target behavior.
- R7. Route evaluation returns one core Forward Directive that contains the unchanged Signal and a canonical target.
- R8. AgentServer commits before outbound preparation and dispatch. Trace propagation and each selected `prepare_dispatch` callback run once.
- R9. A failed or unknown Bus publish result does not roll back the committed Turn and does not cause an automatic retry.

**Inbound connection behavior**

- R10. The Bus integration reports ready only after the one Bus and all required inbound connection resources are ready.
- R11. A normal connection uses best-effort asynchronous delivery. A durable connection calls the destination and acknowledges only after the required Turn commits.
- R12. Each durable connection keeps one record in flight and retries the correct delivery or acknowledgement stage.
- R13. Reconnect ignores stale process, timer, delivery, and acknowledgement messages from an old Bus connection.
- R14. The live-change policy for the Bus declaration and Bus-source connections must be explicit. OQ3 owns this decision.
- R15. Quiescence must not wait on a durable call into the same AgentServer.
- R24. If live connection changes are allowed, queued old-generation input must be rejected before Turn admission.
- R25. A durable ID is unique on the one Bus, stays bound to one path, and is detached rather than deleted on reconnect or normal shutdown.
- R26. Any operation that replaces a managed memory Bus must state that records and durable cursors reset.

**Portable Agent data and clean removal**

- R16. DSL, Map, mutation, document, and view paths use `%{kind: :bus, name: name}` and one canonical connection shape. Portable data contains no runtime handles.
- R17. Document decode uses only selected trusted providers and does not create atoms from document input.
- R18. Complete validation uses the final candidate Agent, so one mutation batch can add or remove related Bus data, connections, and routes together.
- R19. Agent topology keeps inbound provider connections. A Bus endpoint can be a connection source. Agent-to-Bus output uses Forward.
- R20. Delete the old Manager, Client, DSL, and private topology Bus modules without a compatibility layer.
- R21. Keep the low-level `Jido.Signal.Bus` and `Jido.Signal.Dispatch.Bus` APIs for non-Agent callers.

**Operations and guidance**

- R22. Status and Telemetry identify the Agent, Bus, connection, stage, and result class. They do not record full Signal data or Plugin options.
- R23. Guides and examples show one Bus, multiple inbound paths, normal and durable behavior, outbound Forward, external Bus loss, and memory-store limits.

### Acceptance Examples

- AE1. One Agent with one managed Bus and three inbound connections starts one Bus process and three low-level subscriptions.
- AE2. An Agent with no Bus-source connection creates no low-level subscription.
- AE3. `forward "audit.recorded", to: bus(:orders)` publishes the prepared Signal only after the Turn commits.
- AE4. A failed Turn publishes no forwarded Signal.
- AE5. A failed durable Turn retries the same record and does not acknowledge it.
- AE6. An acknowledgement failure retries acknowledgement without running the committed Turn again.
- AE7. Behavior for a live connection change follows the selected OQ3 policy and does not claim stronger preservation than that policy provides.
- AE8. One mutation batch can add the Bus plugin, an inbound connection, and a Bus forward route when live changes are supported by OQ3.
- AE9. An unknown document target or connection-source kind returns a structured error and creates no atom.
- AE10. A Plugin claim for a reserved or already-owned target kind fails.
- AE11. A Bus that disappears after commit causes a post-commit effect failure without rollback or retry.
- AE12. A restarted managed memory Bus does not claim to retain old records or durable cursors.
- AE13. If OQ3 permits live removal or change, queued input from the old runtime cannot run under the new definition.
- AE14. A failed authoritative configuration write cannot leave runtime resources on uncommitted configuration.
- AE15. A planned managed memory Bus replacement requires explicit reset intent.

### Scope Boundaries

**In scope**

- One unified public Bus plugin.
- Exactly one managed or external Bus per Agent Bus plugin selection.
- Inbound connection authoring and outbound Forward authoring.
- The minimum core extension points selected through OQ1 through OQ4.
- Clean removal of the old integration paths.

**Deferred**

- More than one Bus per Agent.
- Remote Bus discovery and distributed transport.
- Competing durable consumers, dead-letter policy, and outbound retry.
- General transitive loop detection.
- Permanent deletion of a durable cursor.

**Out of scope**

- Plugin replacement of core `agent(...)` or `parent()` targets.
- Runtime PIDs or current Jido instance values in portable Agent data.
- Compatibility aliases or automatic translation for old Bus declarations.
- A hidden subscription that receives all Signals.

### Dependencies

- `Jido.Signal.Bus` supplies start, lookup, publish, subscribe, durable replay, acknowledgement, and reconnect operations.
- Agent topology supplies connection path, source, destination, and `:single` or `:broadcast` delivery.
- Agent Extensions already declare logical endpoint kinds and validate connections.
- The Plugin lifecycle supplies one runtime root, readiness, quiesce, resume, and outbound preparation.

---

## Planning Contract

### Settled Decisions

- KTD1. **Use one public Bus plugin and one Bus.** `(session-settled: user-directed — chosen over a multi-Bus container)`
- KTD2. **Make a clean break.** Delete old modules and data shapes. `(session-settled: user-directed — chosen over compatibility adapters)`
- KTD3. **Let Plugins extend Forward without overriding core targets.** `(session-settled: user-approved — chosen over Plugin replacement of core behavior)`
- KTD4. **Use one core Forward Directive.** Agent, parent, and Plugin targets use the same pure evaluation and post-commit effect boundary.
- KTD5. **Use connections for Bus input.** Do not add an independent `subscribe` declaration.
- KTD6. **Use Forward for Bus output.** Reject Agent-to-Bus and Bus-to-Bus connections in the new design.
- KTD7. **Keep `jido_signal` unchanged unless a missing low-level operation is proved.**

### Research Findings

1. `lib/jido/plugin/bus/dsl.ex` already limits its authoring data to one local Bus. The one-Bus constraint matches the current declaration model.
2. `lib/jido/agent/topology.ex` gives a connection the identity `{from, to, path}`. There is no independent connection name and no provider option field.
3. `lib/jido/agent_server/topology_bus.ex` starts a private Bus, attaches one `"**"` subscription, and sends all input back to AgentServer.
4. `lib/jido/agent_server/topology_runtime.ex` then filters that input by the Bus-source connection path and delivers it to root or child Agents.
5. `lib/jido/plugin/bus/client/runtime.ex` has the durable delivery and acknowledgement logic, but it always delivers to the owning root AgentServer.
6. `Jido.Agent.runtime_plugins/1` derives runtime Plugin options only from extension data. It does not include topology connections.
7. Plugin roots start and pass readiness before `CompositionRuntime.reconcile/1` starts topology members. Moving all subscriptions into the Plugin changes the startup window.
8. Changed-Plugin detection compares runtime Plugin declarations. A topology connection change does not currently mark the Bus Plugin as changed.

### Sharp Edges and Blocking Open Questions

#### OQ1. Which destinations can a Bus-source connection use? — Blocking

Current connections can target root or child Agents.
The current Bus Client can only call or cast the root AgentServer.

Options:

1. **Root only.** Require `to: :root` and `delivery: :single`. This reuses the current Client delivery model and avoids a new generic connection-ingress API.
2. **Any Agent endpoint.** Let a connection target root or declared child members. Core must resolve the committed connection and own destination delivery. Durable broadcast must acknowledge only after all selected member Turns commit, and partial success can cause duplicate delivery.

Recommendation: start with root only unless direct Bus-to-child delivery is a required product behavior.

#### OQ2. Who owns subscription startup and reconciliation? — Blocking

The Plugin should own Bus behavior, but Plugin roots start before topology reconciliation.
The current private topology bridge starts in the later composition phase.

Options:

1. **Plugin owns Bus and subscriptions.** Core must pass the Plugin its Bus-source connections. Normal best-effort input can arrive before Agent readiness unless core adds a later activation phase or accepts startup loss.
2. **Plugin owns the Bus; topology runtime owns subscription controllers.** This uses the current lifecycle order, but Bus behavior stays split between Plugin code and core topology code.
3. **Add a two-phase Plugin lifecycle.** Start the Bus root first, reconcile topology, then activate connection resources and complete readiness. This is the cleanest general lifecycle but is a larger core change.

Recommendation: select option 1 only with root-only destinations and an explicit startup-loss rule. Select option 3 if normal input must not be lost during startup.

#### OQ3. What happens when Bus data or Bus-source connections change on a running Agent? — Blocking

The current Plugin lifecycle replaces a changed Plugin root.
Replacing a root that owns a memory Bus destroys its in-memory records and cursors.
The earlier draft added staged in-place Plugin reconfiguration only to avoid this reset.

Options:

1. **Reject live Bus changes.** Bus declaration, Bus-source connections, and Bus Plugin removal are immutable after Agent start. A restart applies a new definition. This needs the least new runtime machinery.
2. **Allow full-root replacement.** Require explicit reset intent for a managed memory Bus and document data loss. External Bus connections can reconnect.
3. **Add in-place reconciliation.** Keep the Bus root and unchanged controllers alive. This requires new generic Plugin lifecycle callbacks, generation-gated input, and failure rules across the commit boundary.

Recommendation: use option 1 unless live topology mutation is a required Bus feature. Do not add option 3 only for convenience.

#### OQ4. How much identity and configuration does a connection need? — Blocking

The current connection schema has `path`, `from`, `to`, and `delivery`.
Bus subscriptions also need selector, durable ID, start position, retry delay, and timeout.
The current identity `{from, to, path}` rejects two connections with the same endpoints and path.

Options:

1. **Add `options: %{}` only.** The source provider normalizes the Map. Keep `{from, to, path}` as identity. This permits one subscription for each relationship and path.
2. **Add `options` and `as`.** `as` gives each connection a stable name and permits two subscriptions with the same endpoints and path. Mutation and document identity rules must change.
3. **Keep options in a separate subscription list.** This restores the duplicate authoring model and conflicts with KTD5.

Recommendation: use option 1 until a real same-path duplicate use case exists.

### Minimum Extension Points if the Recommended Simple Choices Win

This section is a candidate, not an approved implementation contract.
It assumes root-only destinations, Plugin-owned subscriptions, immutable live Bus data, and unnamed connections.

1. Add Plugin-owned forward target callbacks to `Jido.Agent.Extension` and one matching post-commit dispatch callback to `Jido.Plugin`.
2. Keep the existing endpoint declaration and connection validation model. Constrain Bus endpoints to connection sources.
3. Add one canonical connection `options` Map and one provider callback that normalizes options for a source-owned connection.
4. Add an Agent Extension callback such as `runtime_options/2`. It derives runtime Plugin options from normalized extension data and the complete normalized definition. The Bus provider uses it to include only its one Bus and its Bus-source connections.
5. Let existing changed-Plugin comparison see these derived options. If OQ3 selects immutability, reject the change before commit instead of adding staged reconfiguration.
6. Reuse the current Client normal and durable delivery logic inside the unified Plugin root.
7. Add the forward-target codec and safe-view hooks required by R5 through R9.

This candidate does not add `Jido.Plugin.Init.connections`, a generic provider connection-ingress protocol, or staged in-place Plugin reconfiguration.

### Complexity Added by the Broader Choices

| Choice | Extra core work |
|---|---|
| Child Agent destinations | Committed connection lookup, child delivery, durable broadcast result aggregation, and partial-commit retry rules. |
| No startup loss | A two-phase Plugin activation and readiness order around topology reconciliation. |
| Live in-place changes | Prepare, apply, abort, generation rotation, queued-input rejection, and post-commit recovery rules. |
| Named duplicate connections | New connection identity in directives, diffs, codecs, documents, tests, and runtime reconciliation. |

### Alternatives Rejected Now

| Alternative | Reason |
|---|---|
| Keep Manager and Client as separate public Plugins | It keeps ordering rules and prevents several inbound paths through one selected Client module. |
| Let one Agent declare several buses | The requested boundary is one Bus. Multiple inbound paths do not require more buses. |
| Add an independent `subscribe` DSL entity | A connection already states source, destination, and path. The second entity duplicates the relationship. |
| Keep Agent-to-Bus topology delivery | `forward` is the clearer outbound route and is the requested extensibility point. |
| Add staged reconfiguration by default | It is a large lifecycle feature and is not required if live Bus changes are rejected. |

### Planning Completion Gate

The plan becomes `implementation-ready` only after OQ1 through OQ4 are resolved.
The next revision must then:

- remove rejected branches from this document;
- define only the selected core extension points;
- add ordered implementation units with exact repo-relative files;
- add tests for each selected behavior;
- add the final verification commands and Definition of Done;
- run the normal plan confidence and document-review checks.

---

## Sources

- `lib/jido/plugin/bus/dsl.ex`
- `lib/jido/plugin/bus/manager.ex`
- `lib/jido/plugin/bus/manager/server.ex`
- `lib/jido/plugin/bus/client.ex`
- `lib/jido/plugin/bus/client/runtime.ex`
- `lib/jido/agent/extension.ex`
- `lib/jido/agent/topology.ex`
- `lib/jido/agent/dsl/topology.ex`
- `lib/jido/agent/mutation.ex`
- `lib/jido/agent.ex`
- `lib/jido/plugin/init.ex`
- `lib/jido/agent_server/plugin.ex`
- `lib/jido/agent_server/topology_bus.ex`
- `lib/jido/agent_server/topology_runtime.ex`
- `lib/jido/agent_server.ex`
- `examples/07_topology/07_03_bus_swarm/swarm.ex`
- `test/contract/jido.plugin/bus/bus_contract_test.exs`
- `docs/design/02_agent-authoring/design.md`
- `docs/design/05_plugins/design.md`
- `docs/design/10_runtime-topology/design.md`
