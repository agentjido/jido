# 05 — Plugins

> Pending approval. Selected decisions are recorded in the owner design.

## Briefing

A Plugin is one module with optional callbacks for four owners. Implement
only the callbacks it needs. The compiler selects capability groups from
those callbacks; authors do not select separate facet modules:

| Owner | Core support | Authority |
| --- | --- | --- |
| Agent | `Jido.Agent.Plugin` | Pure package input, one owned state field, and owned Directives |
| Agent Server | `Jido.AgentServer.Plugin` | Narrow admission, runtime, readiness, outbound preparation, and post-commit dispatch |
| Persistence | `Jido.Persistence.Plugin` | Dump and load one owned state value |
| Topology | `Jido.Topology.Plugin` | Add static Topology entries |

Before selection, an Agent Plugin can reject or return one portable input under
its package `prepared` slot. After an Action or Flow succeeds, the pipeline
protects Plugin-owned state, validates each Directive once, and calls each
`reduce/2` callback in declaration order.

Agent Plugins cannot change Signals, caller context, Agents, routes, or another
package's input. Agent Server Plugins receive a read-only admission value and
can return only their own `runtime` input. Actions and Flows own domain
calculations and produce the complete Directive list.

An implemented `after_commit/3` hook is a required step after commit and
caller confirmation, before Directives. It receives the exact committed
owned state and version. Failure stops later hooks and Directives while
the commit and caller result remain intact. Startup and restore rebuild
runtime state from `Jido.Plugin.Init`; earlier hooks are not replayed.
Telemetry provides optional observation.

## Current state

- Narrow pure preparation and the post-execution Agent Plugin pipeline are implemented.
- The evaluator uses one internal `run/5` entry point.
- Plugin state remains in the complete `Agent.state` map.
- Agent Server, Persistence, and Topology facets keep their existing owner
  contracts.
- The user selected one Plugin module in GAP-018. Larger Plugins can
  delegate internally without adding public roles or facet configuration.
- The user selected removal of Scheduler durable delivery in GAP-023.
  Its source cleanup remains. The target keeps OTP scheduling and saved
  recurring definitions, with no replay promise for missed ticks.

## Major gaps and work remaining

- Remove Scheduler pending deliveries, business retries, enqueue controls,
  and acknowledgement APIs under GAP-023. Keep saved recurring definitions.
- Refresh remaining built-in capability and runtime evidence under GAP-024–025.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
