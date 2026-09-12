# 05 — Plugins

## Briefing

A Plugin package can select four owner facets:

| Owner | Facet | Authority |
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

Plugin callbacks are value contracts. They can run in a direct caller process
or in an Agent Server-owned Task. A callback must not treat its caller PID or
process dictionary as Agent Server identity. It must not make a synchronous
call back into the same Agent Server activation that is waiting for it.

## Current state

- Narrow pure preparation and the post-execution Agent Plugin pipeline are implemented.
- The evaluator uses one internal `run/5` entry point.
- Plugin state remains in the complete `Agent.state` map.
- Agent Server, Persistence, and Topology facets keep their existing owner
  contracts.
- The mixed package declaration form remains in the normalizer and is a
  separate cleanup item.

## Major gaps and work remaining

- Remove the mixed package declaration form after built-in Plugins move to
  explicit facet manifests.
- Prove that callback results and order are unchanged when live callbacks move
  into Agent Server-owned Tasks.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
