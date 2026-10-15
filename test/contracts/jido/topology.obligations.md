---
modules:
  - Jido.Topology
  - Jido.Topology.DSL.Compiler
  - Jido.Topology.Extension
  - Jido.Topology.Validation
  - Jido.Topology.Source
  - Jido.Topology.Composition
  - Jido.Topology.Plan
  - Jido.Topology.Reference
  - Jido.Topology.Ref
  - Jido.Topology.Plugin
  - Jido.Topology.Child
  - Jido.Topology.Codec
  - Jido.Topology.Codec.Deriver
  - Jido.Topology.Codec.Value
---

## Purpose

Protect Topology authoring, its shared Agent host, static definitions, pure
planning, and supported documents before compiler consolidation. Public DSL
syntax stays unchanged. AgentServer, Controller, Runtime, deployment,
persistence, supervision, and effect dispatch are outside this component.
The module list selects mutation targets; it does not expose internal APIs.

The graph document does not represent the root Agent definition. A complete
combined authoring document needs a separate format decision. Root `vsn`
options on `use Jido.Topology` remain Agent fields and do not enter graph
validation. The guards cover both the default and an explicit version.

## Obligations

### jido.topology.I1 — Shared Agent host

- **scope:** `Jido.Topology.__using__/1`
- **must:** A Topology module provides a neutral Agent definition, default version, domain and complete schemas, Plugins, routes, inline Actions, Signal helpers, and direct commands through the normal Agent API.
- **why:** Topology extends the Agent authoring surface.
- **kind:** functional
- **status:** active

### jido.topology.I2 — Constructor meanings

- **scope:** `Jido.Topology.__using__/1`, `Jido.Topology.new/1`, `Jido.Topology.new!/1`
- **must:** Keep generated public names and arities. Definition and owner access return the Agent definition. new_agent creates an Agent instance. topology returns a graph definition. new/1 creates a Topology instance. Raising constructors raise the corresponding validation error.
- **why:** Consolidation must preserve supported entry points.
- **kind:** functional
- **status:** active

### jido.topology.I3 — Separate authored roles

- **scope:** `Jido.Topology.__using__/1`
- **must:** Agent and Topology blocks are independently optional. Routes require an explicit Agent block. Agent state, schemas, and metadata remain distinct from graph input, schema, and metadata.
- **why:** Shared authoring must preserve each field's meaning.
- **kind:** functional
- **status:** active

### jido.topology.I4 — Authoring evaluation

- **scope:** `Jido.Topology.__using__/1`
- **must:** Evaluate computed options once. Accept supported map, keyword, expression, and module-attribute options. Deferred blocks retain caller values and aliases.
- **why:** Compiler consolidation must preserve Elixir evaluation and scope.
- **kind:** functional
- **status:** active

### jido.topology.I5 — Extension lowering

- **scope:** `Jido.Topology.__using__/1`, `Jido.Topology.Extension.lower/3`
- **must:** Run each supported Agent and Topology extension callback once in declaration order. Consume extension entities, reject duplicate extensions, and validate lowered core configuration. Inline routes retain their helper and execution behavior.
- **why:** Extensions must use the common definition boundaries.
- **kind:** ordering
- **status:** active

### jido.topology.I6 — Current dependency contracts

- **scope:** `Jido.Topology.__using__/1`, `Jido.Topology.instantiate/2`
- **must:** Owner construction, definition access, complete schemas, and member planning read current Action and Plugin contracts after reload.
- **why:** Reuse must not retain stale derived contracts.
- **kind:** functional
- **status:** active

### jido.topology.I7 — Equivalent graph forms

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.Codec.decode/2`, `Jido.Topology.Codec.decode/3`
- **must:** Equivalent supported module, map, keyword, and JSON graph forms produce equal normalized definitions and plans for the same instance options.
- **why:** Each graph authoring form must use the same planning contract.
- **kind:** functional
- **status:** active

### jido.topology.I8 — Input and defaults

- **scope:** `Jido.Topology.instantiate/2`
- **must:** Validate graph input separately from Agent state. Apply input defaults and preserve supplied false and zero. Resolve input and member references before member state validation.
- **why:** Defaults and references must preserve authored values.
- **kind:** functional
- **status:** active

### jido.topology.I9 — Member sources

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.instantiate/2`
- **must:** Agent and group declarations select exactly one current module or neutral Agent definition. Reject instance sources and invalid contracts. Validate resolved member state before activation and retain authored source definitions in the plan.
- **why:** Plans must contain valid member declarations.
- **kind:** functional
- **status:** active

### jido.topology.I10 — Deterministic bounded expansion

- **scope:** `Jido.Topology.instantiate/2`
- **must:** Counted, keyed, and empty groups produce deterministic escaped identities, member state, and layers. Reject duplicate or missing member keys, invalid counts, and expansion beyond max_agents before large allocation.
- **why:** Input order and large counts must not corrupt plans.
- **kind:** functional
- **status:** active

### jido.topology.I11 — Graph relationships

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.instantiate/2`
- **must:** Preserve ownership policy, subscriptions, placement, and dependency order. Reject cycles, absent endpoints, duplicate names, and multiple owners.
- **why:** Plans must preserve one valid dependency graph.
- **kind:** ordering
- **status:** active

### jido.topology.I12 — Static composition

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.instantiate/2`
- **must:** Includes isolate scope, input, and identity. Bind imports explicitly and expose only declared exports of the correct kind. Repeated includes can share a declared Bus without sharing member state.
- **why:** Composition must preserve public endpoints and ownership.
- **kind:** functional
- **status:** active

### jido.topology.I13 — Plugin contributions

- **scope:** `Jido.Topology.instantiate/2`
- **must:** Apply Agent contributions then group contributions in declaration and Plugin order, within each include scope. Validate combined entries and contribution ownership. Preserve application rejection reasons. Callback faults and invalid results retain structured execution errors, Plugin identity, callback codes, and caught causes; invalid entries retain validation errors.
- **why:** Contributions must compose before activation.
- **kind:** ordering
- **status:** active

### jido.topology.I14 — Pure reusable planning

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.instantiate/2`, `Jido.Topology.Codec.decode/3`
- **must:** Authoring and planning do not start runtime processes. Preserve source definitions and documents when applying contributions. Repeated instances isolate identity and input; failure does not prevent later valid planning.
- **why:** Definition and planning operations must remain reusable value operations.
- **kind:** functional
- **status:** active

### jido.topology.I15 — Error boundaries

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.instantiate/2`, `Jido.Topology.__using__/1`
- **must:** Reject unknown fields, duplicate DSL options, improper collections, runtime authoring data, invalid references, and invalid options with structured errors. Compilation retains useful file and line locations. Source provider exceptions, throws, and exits retain their causes. Message wording remains open.
- **why:** Callers need inspectable failures without losing authored locations.
- **kind:** functional
- **status:** active

### jido.topology.I16 — Definition documents

- **scope:** `Jido.Topology.Codec.encode/1`, `Jido.Topology.Codec.encode/2`, `Jido.Topology.Codec.decode/2`
- **must:** Preserve version 2 module documents and version 3 neutral-member and child documents. Enforce strict fields, trusted Registry resolution, document bounds, and omission of instance and runtime data. Nested definitions and references retain their meaning.
- **why:** Documents must remain static and compatible.
- **kind:** persisted-format
- **status:** active

### jido.topology.I17 — Child declaration boundaries

- **scope:** `Jido.Topology.new/1`, `Jido.Topology.instantiate/2`, `Jido.Topology.__using__/1`
- **must:** Preserve child directors, input mapping, activation, gates, and restart limits. Validate static endpoints and resolved command members. Infer a module director only from an explicit Agent block. Static includes reject runtime children.
- **why:** Authoring cleanup must preserve the boundary between static composition and separate runtimes.
- **kind:** functional
- **status:** active
