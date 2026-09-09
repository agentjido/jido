> Approved seam review entry point. Package-specific compatibility evidence
> can evolve with the ecosystem.

# 90 — Package and extension boundaries

## Briefing

Jido is the local Agent coordination package above `jido_action` and
`jido_signal`. The recommended target keeps Agent semantics, live commit,
local runtime, persistence record meaning, static local Topology, public
errors, and semantic observation in Jido. It keeps general durable recovery,
cluster policy, transport gateways, AI policy, browser sessions, and
application architecture outside Jido. The main change is one clear selection
rule for each extension category and one public-contract test for ecosystem
packages.

The Overview and the nine package-boundary decisions were approved on
2026-09-09. The selected core APIs and migration limits are implemented. This
does not mean that every future integration package exists or has V3
compatibility evidence.

Seam 12 was approved before this formal prerequisite. Its error contracts
remain approved. Its public-value ownership statements need a small
revalidation against this seam when they next change.

## Why this seam exists

- Owner: the Jido package boundary and its public extension policy.
- Owns: package responsibility, dependency direction, extension categories,
  rules for new core contracts, and cross-package compatibility gates.
- Does not own: exact Agent Ref fields, Plugin callbacks, persistence record
  fields, Agent Server lifecycle order, error shapes, or package-specific
  adapter APIs.

## Current and target state

| Area | Canonical current state | Recommended target |
| --- | --- | --- |
| Dependency direction | Jido uses `jido_action` and `jido_signal`. The lower packages do not depend on Jido. | Keep both packages below Jido and use only their public contracts. |
| Core scope | Jido owns immutable Agents, Plugins, Directives, Agent Server, persistence policy, local instances, static Topology, and observation. | Keep Jido a complete local Agent runtime, not an application platform. |
| Extension types | Actions, Signals, Plugins, adapters, authoring extensions, Directives, Telemetry, and application wrappers all have public entry points. | Keep each category distinct and select it by authority and lifecycle need. |
| Runtime APIs | Instance lifecycle helpers, Ref-first instance functions, and public PID-based Agent Server commands coexist. Generated-name helpers are public. | Preserve them until a separate staged migration has proof. |
| Persistence | Jido owns compatible and stable Ref record meaning. Byte adapters provide compare-and-swap. An Agent can override instance persistence. | Keep the adapter contract and the explicit legacy collision and no-automatic-rewrite rules. |
| Ecosystem scope | AI V3 uses sibling Jido packages. Browser still declares V2 Jido dependencies. Durable, cluster, and fabric package APIs are not proved here. | Require one tested V3 package set before an integration package claims compatibility. |

## Evolution work

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Public extension inventory | Seam 12 now records public values, raw controls, and internal support types. | Preserve the classified inventory through delivery. | 90 Package boundaries, 12 Errors and contracts, 99 Delivery |
| Stable identity boundary | Agent Ref and the local Ref-first facade are implemented beside IDs, PIDs, and generated names. | Preserve all compatible identity forms through V3. | 03 Agent identity, 09 Jido instance, 12 Errors and contracts |
| Persistence ownership | Instance defaults and per-Agent overrides coexist. Backend and migration owners are not final. | One approved authority model that keeps the byte adapter and has a staged migration. | 07 Persistence, 09 Jido instance, 90 Package boundaries |
| Ecosystem contract proof | The unpacked core package passes a public-only consumer against one exact V3 matrix. | Each added integration package supplies its own matrix and fixture. | Integration package owner |
| Future service scope | Durable, cluster, and transport capability lists have no released package contracts. | Capability ownership without claims of available package APIs. | Future package owners, 99 Delivery |
| Integration ownership | AI and browser ownership is clear at a high level, but V3 compatibility is not complete. | Public Action, Signal, Plugin, Directive, and instance integration with no private Jido access. | `jido_ai`, `jido_browser`, 90 Package boundaries |

## Approved direction

The user approved these decisions on 2026-09-09.

1. **Core Bright Line:** Approve Jido as the local Agent coordination layer
   above `jido_action` and `jido_signal`.
2. **Extension selection:** Approve ordinary composition as the default, with
   Plugins, adapters, authoring extensions, Directives, and Telemetry used only
   for their defined authority.
3. **Compatibility:** Keep all current supported package APIs until an owner
   seam approves and proves a staged migration.
4. **Storage ownership:** Keep record meaning and lifecycle policy in Jido.
   Defer backend placement and per-Agent override changes to seams 07 and 09.
5. **External services:** Keep durable recovery, cluster policy, transport,
   AI-provider policy, and browser sessions outside Jido core.
6. **Future names:** Treat `jido_durable`, `jido_cluster`, and `jido_fabric` as
   working package names, not as available or locked APIs.
7. **Release gate:** Prove one explicit `jido`, `jido_action`, and
   `jido_signal` set through public contracts before a core release claim.
   Each integration package proves its own added compatibility.
8. **Stored data:** Keep core record, Agent state, Plugin state, and backend
   storage migration ownership separate.
9. **Boundary evidence:** Use a small public-only fixture when an integration
   package makes a V3 compatibility claim. Internal core tests are not the only
   evidence for that claim.

## Dependencies

- Approved prerequisite: [00 Overview](../00_overview/README.md).
- Early approved dependent: 12 Errors and contracts. Its public ownership
  inventory was revalidated after the owner-seam changes.
- Other dependents: all owner seams that expose public values, integration
  packages, and 99 Delivery.
- Blockers: None for the selected core package set. Future package APIs and
  integration evidence remain owner work.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
