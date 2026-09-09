> Selected and implemented four-owner Plugin seam.

# 05 — Plugins

## Briefing

Jido now separates one Plugin package across four closed owner facets:

| Owner | Public facet | Authority |
| --- | --- | --- |
| Agent | `Jido.Agent.Plugin` | Pure Turn preparation, owned state, and owned Directives |
| Agent Server | `Jido.AgentServer.Plugin` | Live admission, runtime, readiness, outbound preparation, and post-commit dispatch |
| Persistence | `Jido.Persistence.Plugin` | Pure dump and load of one paired owned-state value |
| Topology | `Jido.Topology.Plugin` | Pure canonical Bus, ownership, and subscription entries |

A callback-free package module uses `Jido.Plugin` to name no more than one
module for each facet. Normalization produces one neutral manifest and four
separate internal Specs. Each owner Spec excludes fields owned by the other
facets.

Agent preparation uses declared domain-state observations and a separate
prepared input for each package. Route selection is fixed from the unchanged
source Signal before preparation. The selected executable receives the input
map as `context.plugin_inputs`. An Agent facet can later replace only its own
complete state value and append only its owned Directives.

The existing mixed `use Jido.Plugin` behavior remains as an explicit
compatibility form. Existing built-ins do not need a same-release rewrite.

## Source structure

- `Jido.Plugin` defines package manifests and compatibility delegates.
- `Jido.Plugin.Normalizer` classifies package and legacy declarations.
- Each owner module defines and runs only its facet callbacks.
- Public callback values live below their owner module.
- `Jido.Plugin.Spec` and all owner Specs remain internal implementation data.

The former 1,181-line mixed implementation is split across these owner files.

## Current state

- The package manifest and four facet behaviors are implemented.
- Agent and Agent Server call their owner modules.
- Persistence and Topology facet conversion functions are implemented and
  bounded. Persistence record use and Topology plan use are complete.
- Each Plugin runtime generation receives matching committed Plugin state and
  state version in its immutable Init value.
- The Plugin-isolation research example passes all four assertions.
- The selected four-owner contract and all owner integrations are implemented.

## Dependencies

- Prerequisites: seams 90, 12, 01, 02, 03, and 04.
- Completed owner integrations: seam 07 records, seam 08 runtime bootstrap,
  and seam 11 static Topology planning.
- Other dependents: seams 06, 10, 13, and 99.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
