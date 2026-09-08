> Seam review entry point. This document is pending approval.

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

The Overview is a draft prerequisite. Its review status is `Pending approval`.
This seam uses its Bright Line and package direction only as assumptions. It
does not call the Overview approved.

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
| Runtime APIs | Instance lifecycle helpers and public PID-based Agent Server commands coexist. Generated-name helpers are public. | Preserve them. Add any Ref-first or instance command facade before a staged migration. |
| Persistence | Jido owns record meaning. Byte adapters provide compare-and-swap. An Agent can override instance persistence. | Keep the adapter contract. Resolve storage authority and migration rules in seams 07 and 09 before a change. |
| Ecosystem scope | AI V3 uses sibling Jido packages. Browser still declares V2 Jido dependencies. Durable, cluster, and fabric package APIs are not proved here. | Require one tested V3 package set before an integration package claims compatibility. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Public extension inventory | Supported APIs have no one retention and migration register. | One classified inventory with support and migration status. | 90 Package boundaries, 12 Errors and contracts, 99 Delivery |
| Stable identity boundary | Current packages can use IDs, PIDs, and generated names, but core has no stable Agent Ref. | An additive identity boundary before any PID or name restriction. | 03 Agent identity, 09 Jido instance, 12 Errors and contracts |
| Persistence ownership | Instance defaults and per-Agent overrides coexist. Backend and migration owners are not final. | One approved authority model that keeps the byte adapter and has a staged migration. | 07 Persistence, 09 Jido instance, 90 Package boundaries |
| Ecosystem contract proof | Core tests do not prove that a released package uses only public contracts. | A public-only fixture and one compatible V3 package matrix. | 90 Package boundaries, 99 Delivery |
| Future service scope | Durable, cluster, and transport capability lists have no released package contracts. | Capability ownership without claims of available package APIs. | Future package owners, 99 Delivery |
| Integration ownership | AI and browser ownership is clear at a high level, but V3 compatibility is not complete. | Public Action, Signal, Plugin, Directive, and instance integration with no private Jido access. | `jido_ai`, `jido_browser`, 90 Package boundaries |

## Decisions requested

All decisions are recommendations and are pending approval.

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
7. **Release gate:** Require a public-only extension fixture and one explicit
   compatible V3 package set before release claims.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/README.md), used as a draft
  prerequisite only.
- Dependents: 12 Errors and contracts, all owner seams that expose public
  values, and 99 Delivery.
- Blockers: The Overview and all decisions in this seam are pending approval.
  Production adapter placement, stable identity, and storage authority also
  need owner-seam decisions.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
