---
modules:
  - Jido.AgentServer.CompositionRuntime
  - Jido.AgentServer.TopologyRuntime
  - Jido.AgentServer.TopologyBus
---

## Purpose

Protect live child and connection resources that follow accepted Agent data.
This component does not own pure topology data validation, Turn evaluation,
Plugin callback behavior, effect ordering, or durable storage.

The public boundary is the child and member API on `Jido.AgentServer`.
`CompositionRuntime`, `TopologyRuntime`, and `TopologyBus` are internal. The
logical topology and Bus declarations belong to the `Jido.Agent` DSL; this
runtime component has no separate DSL.

## Obligations

### jido.agent_server.composition.I1 — Owned child activations

- **scope:** `Jido.AgentServer.spawn_child/4`, `children/2`, `stop_child/3`
- **must:** Start each tagged owned child under the parent activation. Report its current worker and activation separately after worker or root recovery. Stop its complete activation tree, nested children, and Plugin roots on explicit child stop or parent activation shutdown. A bare worker cannot own children.
- **why:** Logical child identity and OTP ownership must stay distinct.
- **kind:** functional
- **status:** active

### jido.agent_server.composition.I2 — Independent child lifetime

- **scope:** `Jido.AgentServer.spawn_child/4`
- **must:** Start independent children under the Jido instance. On parent activation loss, apply stop, continue, or emit_orphan. A continuing child keeps its runtime resources and can execute. An orphan Signal uses `jido.agent_server.orphaned`, runs under one finite owned dispatch budget, and must settle before adoption. Keep relationship data outside Agent state.
- **why:** Parent loss must have one explicit child-lifetime result.
- **kind:** ordering
- **status:** active

### jido.agent_server.composition.I3 — Safe adoption

- **scope:** `Jido.AgentServer.adopt_child/4`
- **must:** Adopt only an unattached independent activation in the same instance and partition. Reject self-adoption, cycles, concurrent cycle creation, cross-instance children, bare workers, unavailable ancestry, and pending orphan delivery. Preserve the child and release the tag after rejection. Preserve an accepted relationship through worker recovery. Release it after whole child-root replacement.
- **why:** Adoption must not create an invalid or uncertain ownership graph.
- **kind:** ordering
- **status:** active

### jido.agent_server.composition.I4 — Child admission and cleanup

- **scope:** child start, stop, and adoption
- **must:** Validate the complete child, unique tag, placement, restart policy, parent-loss policy, server options, relationship metadata, instance, and orphan dispatch before ownership changes. Child server options accept runtime settings only and cannot replace identity or ownership. Adoption cannot reconfigure the existing child server. Reserve each tag once. Release reservations, caller monitors, roots, and terminal child records after failure or confirmed stop. A dead startup caller cannot attach an old child after tag reuse. If a new root has no live worker, stop it and return worker_unavailable.
- **why:** Failed or concurrent child operations must not leak ownership.
- **kind:** ordering
- **status:** active

### jido.agent_server.composition.I5 — Accepted composition commit

- **scope:** route, Plugin, topology, and connection mutations
- **must:** Validate the complete runtime target before commit. Commit accepted composition data in one Agent revision and do not execute its mutation Directives as effects. Reject a live-resource change on a bare worker. Preserve the prior Agent and revision after rejection. Hand accepted Plugin declarations to the Plugin runtime owner.
- **why:** Accepted Agent data must be the authority for live composition.
- **kind:** ordering
- **status:** active

### jido.agent_server.composition.I6 — Member reconciliation and readiness

- **scope:** accepted topology agent declarations
- **must:** Bind member counts and initial state from the accepted parent state. Preserve stable slot identities for unchanged persistent members, and assign a new identity when a removed or changed slot starts a new lifetime. Keep unchanged member processes, replace changed members, stop removed members, and start missing members under the owning activation. Keep admission closed until every required member is ready.
- **why:** Live members must match one accepted composition revision before later Turns run.
- **kind:** ordering
- **status:** active

### jido.agent_server.composition.I7 — Accepted resource recovery

- **scope:** AgentServer startup, worker recovery, and post-commit reconciliation
- **must:** Rebuild accepted topology members and local buses before readiness without saving process handles. A post-commit resource failure must not undo the accepted local or durable checkpoint and must not reopen admission. Recovery must rebuild the accepted target and keep unaffected members during an ordinary live reconciliation.
- **why:** Runtime resources are derived from accepted data and cannot become a second authority.
- **kind:** ordering
- **status:** active

### jido.agent_server.composition.I8 — Connection and Bus ownership

- **scope:** accepted topology connections and declared local Buses
- **must:** Deliver outputs through accepted connections, including counted broadcast, child-to-root, and Bus routes. Accepted connections take priority over default dispatch. Create local Buses only from explicit Bus declarations. Own their bridge, Bus, and subscription under the activation and remove them with it.
- **why:** Connection delivery must use the same accepted resource generation.
- **kind:** functional
- **status:** active

### jido.agent_server.composition.I9 — Runtime child restart policy

- **scope:** runtime Agent start and stop Directives
- **must:** Restart permanent runtime Agents after worker stop. Remove a permanent supervisor entry after explicit stop. Do not restart temporary runtime Agents, and release their names and child tags after stop so a later start can reuse them.
- **why:** Runtime child lifetime is a composition rule, not an effect-delivery rule.
- **kind:** functional
- **status:** active

### jido.agent_server.composition.I10 — Public composition API

- **scope:** `Jido.AgentServer.spawn_child/4`, `children/2`, `members/3`, `stop_child/3`, `adopt_child/4`
- **must:** Keep the exact composition operations on the documented `Jido.AgentServer` facade. Document and type child tags, live child records, spawn options, adoption options, results, and errors. Keep composition runtime modules internal. Do not add a second runtime DSL.
- **why:** Users need one stable composition boundary without access to resource-hosting internals.
- **kind:** functional
- **status:** active
