> Seam review entry point. This refinement is pending approval. It keeps the
> implemented Agent Server behavior and proposes a smaller internal design.

# 08 — Agent Server

## Briefing

`Jido.AgentServer` stays as the public module. Existing code can still call
`Jido.AgentServer.start_link/1`, use its child specification, send Signals with
`call/3` or `cast/2`, use the OTP asynchronous request functions, and use the
current control, inspection, lifecycle, debug, child, and upgrade functions.

The proposed change is internal. `Jido.AgentServer` becomes a thin public
facade. A private `Jido.AgentServer.Runtime` implements `:gen_statem` and owns
the live activation. The facade does not start a second process. The PID
returned by `start_link/1` is the Runtime PID.

The Runtime has one narrow purpose: it is the serialized authority for one
committed Agent, one state version, and at most one active Turn. It accepts
events, changes phase, starts owned work, accepts valid work results, commits
state, and applies lifecycle decisions. User callbacks, storage calls, remote
calls, and other work that can block run outside the Runtime process.

This split keeps the current semantics. It does not change OTP postponement,
commit order, persistence authority, Plugin readiness, parent-child behavior,
public phases, Turn Outcomes, or current compatibility APIs.

Code and executable tests are canonical for current behavior. The target
design in this seam is a proposal until it is approved and implemented.

## Why this seam exists

- Public owner: `Jido.AgentServer`, as the stable API facade.
- Runtime owner: private `Jido.AgentServer.Runtime`, as the only live commit
  authority for one activation.
- Owns: Signal admission, serialization, phase transitions, active-work
  identity, cancellation, commit coordination, Directive settlement control,
  local relationship projection, Plugin runtime links, hibernation, and stop.
- Does not own: Agent construction meaning, route or candidate meaning, Plugin
  facet contracts, persistence record meaning, stable Ref fields, instance
  lookup, placement policy, cluster authority, transport, or application
  architecture.

## Current behavior and proposed shape

| Area | Current behavior to keep | Proposed internal shape |
| --- | --- | --- |
| Public API | `Jido.AgentServer` starts and controls the OTP process directly. | Keep every documented entry on the facade. Delegate to the private Runtime. |
| Process model | One `:gen_statem` owns one Agent, one version, and at most one Turn. | Keep one process. Do not add a facade process. |
| Admission | OTP postpones busy Signals. A token set limits only callbacks already seen by the state machine. | Keep OTP postponement and delivery order. Do not add a second Signal queue. |
| Execution | Admission and executable work already use owned tasks in important paths. Some preparation and finalization still run in the state machine. | Put all user code and blocking work in owned, supervised work units. Keep decisions in Runtime. |
| Commit | A checkpoint or durable CAS succeeds before live replacement, reply, and Directives. | Keep this exact order. Run storage work outside Runtime and accept only a fenced result. |
| Effects | Directives run in order after commit. | Keep ordered settlement. Put external and user work outside Runtime. Apply returned runtime changes in Runtime. |
| Plugins | Runtime generations are readiness-gated and use matching committed state and version. | Keep Plugin processes and handles separate from logical Agent children. |
| Relationships | Parent and child Agent Servers are OTP peers. The Server keeps a live relationship projection and Runtime Store keeps a child-to-parent binding. | Keep the V2 recovery model. Add V3 activation and spawn-generation checks. Put relationship transitions behind one private boundary. |
| Upgrade | Explicit upgrade work waits for idle and can replace one validated Agent definition. | Keep the public operation. Run the supplied callback and migration outside Runtime. |

## Relationship model

The relationship model keeps the useful V2 design:

- Parent and child Agent Servers are OTP peers. A logical parent does not
  supervise its child process.
- Each child keeps one live parent reference. Each parent keeps its live child
  projection.
- A named instance keeps a small child-to-parent binding in Runtime Store. It
  contains stable identity and relationship data, not PIDs, monitors, or task
  handles.
- After a child restart, the child loads the binding, resolves the current
  parent PID, creates a new monitor, and announces that it is online. The
  parent then rebuilds its live child entry.
- `SpawnRegistry` owns distributed spawn generations and closed request
  history. This data does not belong in the Agent Server relationship value.
- The Agent value and its checkpoint do not contain live parent or child
  references. The V2 `__parent__` and `__orphaned_from__` state injection does
  not return.
- Logical Agent children and Plugin runtime children use separate private
  collections and separate transition code.

Seam 10 owns the full runtime-topology contract. This seam owns only how one
Agent Server keeps and changes its local projection.

## Major gaps and work that remains

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Facade and Runtime are one module | Public API code, OTP callbacks, and internal policy change together. | Keep `Jido.AgentServer` stable and move callbacks to one private Runtime without adding a process. | 08 Agent Server |
| Some slow work runs in Runtime | A user callback, storage adapter, remote call, or finalizer can delay inspection and control. | Runtime starts owned work and accepts only a tagged, current result. | 08, with 04, 05, 07, and 10 contracts |
| Runtime state is broad and flat | Optional task, Plugin, relationship, and lifecycle fields permit invalid combinations. | Use small phase-specific work values and nested capability state. | 08 Agent Server |
| Agent and Plugin children share one map | Two different lifecycle models use one representation and monitor path. | Separate logical Agent relationships from Plugin runtime ownership. | 08 and 10 |
| Relationship rules are spread across files | Adoption, spawn, monitor, restore, persistence, and parent death are hard to verify as one protocol. | Use one pure relationship transition boundary plus bounded effect commands. | 08 and 10 |
| Work messages use several identity forms | Late or duplicate work can be difficult to audit. | Use one work envelope with activation, Turn, work, and expected-version identity where applicable. | 08 and 13 |

## Proposed decisions

1. Keep all documented direct `Jido.AgentServer` APIs, including `cast/2`.
2. Make `Jido.AgentServer` a facade and make a private Runtime the
   `:gen_statem` callback module.
3. Return the Runtime PID from `start_link/1`. Do not add a wrapper process.
4. Keep the public child-spec start MFA on `Jido.AgentServer.start_link/1`.
5. Keep OTP postponement. Do not add a private Signal queue.
6. Keep one serialized Runtime authority. Move work, not authority, to tasks.
7. Keep commit and Directive order exactly as implemented.
8. Keep the V2 logical relationship projection and Runtime Store recovery
   pattern. Add V3 activation and spawn-generation fencing.
9. Keep logical Agent children separate from Plugin runtime children.
10. Keep placement, distributed control, and durable topology outside this
    seam.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md), and
  [07 Persistence](../07_persistence/alignment.md).
- Related input: [02 Agent authoring](../02_agent-authoring/design.md) defines
  canonical construction and generated live-helper delegation.
- Dependents: 09 Jido instance, 10 Runtime topology, 11 Topology control plane,
  13 Observability, and 99 Delivery.
- Seam 09 keeps the Ref-first instance facade. It does not replace the direct
  `Jido.AgentServer` facade described here.

## Documents

- [Target design](design.md)
- [Alignment evidence](alignment.md)
