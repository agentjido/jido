---
modules:
  - Jido.AgentServer.Topology
---

## Purpose

Protect live child and connection resources that follow accepted Agent data.
This component does not own pure topology data validation, Turn evaluation,
Plugin callback behavior, effect ordering, or durable storage.

The public boundary is the child and member API on `Jido.AgentServer`.
`Topology` is the internal live resource owner. The
logical topology and Bus declarations belong to the `Jido.Agent` DSL; this
runtime component has no separate DSL.

## Obligations

### jido.agent_server.composition.I1 — Owned child activations

- **scope:** `Jido.AgentServer.spawn_child/4`, `children/2`, `stop_child/3`
- **must:** Start each tagged owned child under the parent activation. Report its current worker and activation separately after worker or root recovery. Stop its complete activation tree, nested children, and Plugin roots on explicit child stop or parent activation shutdown. A bare worker cannot own children.
- **why:** Logical child identity and OTP ownership must stay distinct.
- **kind:** functional
- **status:** retired

### jido.agent_server.composition.I2 — Independent child lifetime

- **scope:** `Jido.AgentServer.spawn_child/4`
- **must:** Start independent children under the Jido instance. On parent activation loss, apply stop, continue, or emit_orphan. A continuing child keeps its runtime resources and can execute. An orphan Signal uses `jido.agent_server.orphaned`, runs under one finite owned dispatch budget, and must settle before adoption. Keep relationship data outside Agent state.
- **why:** Parent loss must have one explicit child-lifetime result.
- **kind:** ordering
- **status:** retired

### jido.agent_server.composition.I3 — Safe adoption

- **scope:** `Jido.AgentServer.adopt_child/4`
- **must:** Adopt only an unattached independent activation in the same instance and partition. Reject self-adoption, cycles, concurrent cycle creation, cross-instance children, bare workers, unavailable ancestry, and pending orphan delivery. Preserve the child and release the tag after rejection. Preserve an accepted relationship through worker recovery. Release it after whole child-root replacement.
- **why:** Adoption must not create an invalid or uncertain ownership graph.
- **kind:** ordering
- **status:** retired

### jido.agent_server.composition.I4 — Child admission and cleanup

- **scope:** child start, stop, and adoption
- **must:** Validate the complete child, unique tag, placement, restart policy, parent-loss policy, server options, relationship metadata, instance, and orphan dispatch before ownership changes. Child server options accept runtime settings only and cannot replace identity or ownership. Adoption cannot reconfigure the existing child server. Reserve each tag once. Release reservations, caller monitors, roots, and terminal child records after failure or confirmed stop. A dead startup caller cannot attach an old child after tag reuse. If a new root has no live worker, stop it and return its recorded start failure, or worker_unavailable when no reason is recorded.
- **why:** Failed or concurrent child operations must not leak ownership.
- **kind:** ordering
- **status:** retired

### jido.agent_server.composition.I5 — Runtime topology validation

- **scope:** activation startup and `Jido.AgentServer.Topology.validate/1`
- **must:** Validate that each static endpoint has a runtime implementation before the activation becomes ready. Reject unsupported provider endpoints. Create local Buses only from the Bus Plugin declaration.
- **why:** A valid data definition must also have one executable runtime shape.
- **kind:** ordering
- **status:** retired

### jido.agent_server.composition.I6 — Static member startup and readiness

- **scope:** static topology agent declarations
- **must:** Start the fixed member count with the declared initial state. Initialize a new member once with its final child identity and topology context. Restore a saved member without initialization. Preserve durable slot identities across activation recovery. Keep admission closed until every required member is ready.
- **why:** Live members must match the activation definition before commands run.
- **kind:** ordering
- **status:** retired

### jido.agent_server.composition.I7 — Accepted resource recovery

- **scope:** AgentServer startup and worker recovery
- **must:** Rebuild static topology members and local Buses before readiness without saving process handles. A resource startup failure must not open admission. Recovery must rebuild the activation definition.
- **why:** Runtime resources are derived from accepted data and cannot become a second authority.
- **kind:** ordering
- **status:** retired

### jido.agent_server.composition.I8 — Connection and Bus ownership

- **scope:** accepted topology connections and declared local Buses
- **must:** Deliver outputs through accepted connections, including counted broadcast, child-to-root, and Bus routes. Accepted connections take priority over default dispatch. Create local Buses only from explicit Bus declarations. Own their bridge, Bus, and subscription under the activation and remove them with it. A member output or Bus delivery that finds no live destination marks an effect failed and logs its Signal type and reason. The owner keeps running.
- **why:** Connection delivery must use the same accepted resource generation.
- **kind:** functional
- **status:** retired

### jido.agent_server.composition.I9 — Runtime child restart policy

- **scope:** runtime Agent start and stop Directives
- **must:** Restart permanent runtime Agents after worker stop. Remove a permanent supervisor entry after explicit stop. Do not restart temporary runtime Agents, and release their names and child tags after stop so a later start can reuse them.
- **why:** Runtime child lifetime is a composition rule, not an effect-delivery rule.
- **kind:** functional
- **status:** retired

### jido.agent_server.composition.I10 — Public composition API

- **scope:** `Jido.AgentServer.spawn_child/4`, `children/2`, `members/3`, `stop_child/3`, `adopt_child/4`
- **must:** Keep the exact composition operations on the documented `Jido.AgentServer` facade. Document and type child tags, live child records, spawn options, adoption options, results, and errors. Keep composition runtime modules internal. Do not add a second runtime DSL.
- **why:** Users need one stable composition boundary without access to resource-hosting internals.
- **kind:** functional
- **status:** retired

### jido.agent_server.composition.I11 — Controlled declared-subtree removal

- **scope:** `Jido.AgentServer.remove_topology_member/4`
- **must:** Remove one selected declared member slot only from the current root activation. Close admission for the selected member and all owned descendants before shutdown. Finish accepted Turns by default, support explicit pre-commit cancellation, and stop descendants before their parent. Keep the root and sibling subtrees active. Keep the static declaration and durable child records unchanged. Preserve removal through root-worker recovery in the same activation. Return success for a repeated removal. On a timeout or partial shutdown, keep removal intent and closed admission so a repeated call can continue cleanup without restoring the subtree.
- **why:** Applications need one bounded lifecycle operation for a selected static subtree without private topology access or a mutable Agent definition.
- **kind:** ordering
- **status:** active
