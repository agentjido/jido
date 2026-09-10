# 05 — Plugins

## Briefing

A Plugin package can select four owner facets:

| Owner | Facet | Authority |
| --- | --- | --- |
| Agent | `Jido.Agent.Plugin` | One owned state field and owned Directives |
| Agent Server | `Jido.AgentServer.Plugin` | Admission, runtime, readiness, outbound preparation, and post-commit dispatch |
| Persistence | `Jido.Persistence.Plugin` | Dump and load one owned state value |
| Topology | `Jido.Topology.Plugin` | Add static Topology entries |

The Agent Plugin path has one phase. After an Action or Flow succeeds, the
pipeline protects Plugin-owned state, validates Directives, and calls each
`update_state/3` callback in declaration order. The callback receives only its
current owned state and its owned Directives.

Agent Plugins do not prepare input, change Signals, change caller context,
observe domain-state projections, or add Directives. Actions and Flows own
domain calculations and produce the complete Directive list.

## Current state

- The one-phase Agent Plugin pipeline is implemented.
- The pipeline has one internal `run/3` entry point.
- Plugin state remains in the complete `Agent.state` map.
- Agent Server, Persistence, and Topology facets keep their existing owner
  contracts.
- The mixed package declaration form remains in the normalizer and is a
  separate cleanup item.

## Major gaps and work remaining

- Remove the mixed package declaration form after built-in Plugins move to
  explicit facet manifests.
- Review dependent design documents that still describe Agent Plugin
  preparation.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
