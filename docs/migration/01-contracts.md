# Contracts and design decisions

Status: core transfer approved with the implemented donor design. Current source
is `bf6c9fb`. Naming and the required source fixes are complete. The original
`ba00fcf` donor is preserved. The user deferred the redesign proposals.

## Naming contract

The table records the completed donor change. Do not run another rename during
core transfer. Check exact prepared paths and contracts against the manifest.

| Original Actor name | Prepared source and core name | Transfer check |
| --- | --- | --- |
| `Jido.Actor` / `%Jido.Actor{}` | `Jido.Agent` / `%Jido.Agent{}` | Replace the existing implementation; an Elixir alias does not preserve struct identity |
| `Jido.Actor.Server.*` | `Jido.AgentServer.*` | Keep the established server module name; do not introduce `Jido.Agent.Server` |
| `Jido.Actor.Directive.*` | `Jido.Agent.Directive.*` | Transfer prepared directives and constructors |
| `SpawnActor`, `spawn_actor` | `SpawnAgent`, `spawn_agent` | Match the existing domain term |
| `Jido.Actor.Command`, `.Turn`, `.Builder`, `.Codec`, `.DSL`, `.State`, `.Validation` | Equivalent `Jido.Agent.*` names | Transfer implementation and internal references together |
| `Jido.Telemetry.Actor` | `Jido.Telemetry.Agent` | Transfer prepared event producers and tests together |
| `start_actor`, `stop_actor`, `whereis_actor`, `list_actors`, `count_actors` | `start_agent`, `stop_agent`, `whereis_agent`, `list_agents`, `count_agents` | Check option and return contracts; names alone are not compatibility |
| `hibernate_actor`, `thaw_actor` | `Jido.hibernate` and `Jido.thaw` | Transfer prepared calls and completed-stop semantics |
| `actor do`, `actor()`, `actors` | `agent do`, `agent()`, `agents` | Cover Spark entities, generated code, Builder and JSON fields |
| `actor_id`, `actor_state`, `actor_server`, `actor_module` | Equivalent `agent_*` keys | Cover reserved execution context, Plugin Init, metadata, snapshots, and validation |
| `:actor`, `:actor_server`, `jido.actor.*` | Reviewed Agent event and message names | Transfer producers, consumers, metrics, and exact assertions together |
| `jido:actor:v1:` | `jido:agent:v1:` with Agent envelope fields | Do not silently interpret V2 records or donor Actor records as the new format |

The completed naming map preserves Factory identifiers and numeric example
IDs. It maps `Jido.Actor.Server` directly to `Jido.AgentServer`. It qualifies
Elixir process Agent helpers where aliases would conflict. Check the copied
[path map](evidence/prepared/name-path-map.json) and old-format rejection tests.
A raw replacement can corrupt `factory`; do not apply it to prepared source.

The selected persistence prefix is `jido:agent:v1:`. Agent envelopes use
`kind: :agent`, `agent_module`, and `agent_id`. Authoring JSON uses `jido.agent`.
Old Actor keys are not read. An Actor envelope moved to an Agent key is rejected.
Neither Actor nor core V2 data is converted automatically. See the
[serialization contract](evidence/prepared/serialized-formats.md).

An intentional historic reference to `Jido.Actor` can remain in this migration
record. Executable core code, generated names, example code, and current API
documentation must use the selected Agent terms.

## V2 behavior is not preserved by the name

| Boundary | Current core at `10ebacd4` | Implemented donor | Plan |
| --- | --- | --- | --- |
| Command input | Action/instruction-oriented `MyAgent.cmd/2,3` | Signal-oriented command through one Action or Flow | Adopt the Signal path; specify an adapter only for retained public entry points |
| Direct success | `{agent, directives}` | `{:ok, candidate, directives}` | Document the V3 result change; never discard a validation error to mimic V2 |
| State | Strategy state, state operations, patch helpers, default plugins | Complete candidate state; one Plugin-owned state key in the composed state schema | Remove the old state-operation engine; retain its useful invariants as new tests |
| Routing | AgentServer router plus strategy layer | `Command.Runner`, overridable `handle_signal/2`, Plugin preparation before final route resolution | Preserve this order for initial example parity; review the proposed route-first design separately |
| Runtime | GenServer and drain/lifecycle machinery | `:gen_statem`: idle, admitting, running, directing | Replace internals under `Jido.AgentServer` |
| Plugins | Declaration options, manifests, routes, schedules, lifecycle hooks | `prepare`, `admit`, `state_spec`, `update_state`, owned directives, optional runtime and outbound transformation | Replace the contract and built-ins as a unit |
| Persistence | `Jido.Persist` and `Jido.Storage.*` | `Jido.Persistence` and binary adapters with compare-and-swap | Adopt an explicit versioned format; provide a migration/rejection policy for existing data |
| Composition | Pod, managed instances, pools, Sensors | Child ownership, input Plugins, application recovery; additional `Jido.Topology` | Preserve demonstrated capabilities; do not claim Pod or Sensor API compatibility |
| History | Thread/Memory integration helpers | Application-owned state; `Jido.Thread` remains an optional value | Keep data helpers; remove old integration only with a documented replacement |

Evidence: donor `lib/jido/agent.ex`, `lib/jido/agent/command/runner.ex`,
`lib/jido/agent_server.ex`, `lib/jido/plugin.ex`, and `lib/jido/persistence.ex`.
The minimal example compares direct and live results. It also proves that a
failed command preserves the previous committed state.

Actions and Flows may perform external I/O before returning. A failed Turn
does not reverse completed external work. Preserve this limit in the code,
tests, and documentation. Describe deterministic state assembly for fixed
inputs and executable results; do not claim that all execution is pure.

## Implemented behavior versus proposed design

All rows in donor `docs/design/README.md` currently say `Pending approval`.
`v3-design-changes.md` expressly compares the current implementation with a
proposal. Use executable behavior as the transfer baseline and record these
choices before changing it.

| Decision | Proposal in donor design | Implemented evidence and conflict | Recommended transfer choice |
| --- | --- | --- | --- |
| D01 Authoring | Versioned modules only; remove neutral definitions, Builder, Codec, map constructors | Basic authoring tests compare five forms; Workflow inline steps use Builder/JSON; Topology has three forms | Retain implemented forms. Consider extraction to a package after parity, with its own examples |
| D02 Live references | Instance facade is the only public live API; `Agent.Ref` replaces PID calls | Examples call Server APIs and generated helpers with PIDs; no `Jido.Agent.Ref` implementation exists | Keep `Jido.AgentServer` and instance startup APIs. Specify references in a later contract if required |
| D03 Routing and Plugins | Select first route before isolated Plugin preparation; separate `plugin_state`; new Transition/Contribution structs | Runner currently prepares Plugins before selecting a route; Plugin state occupies the composed state; proposed structs are absent | Preserve current behavior for parity. A later pipeline change must update input-order and ownership tests explicitly |
| D04 Relationships | Remove parent tags, adoption, generic Spawn and child policy from core | Multi-agent, Factory, remote ownership and Topology use those operations | Keep implemented ownership. Do not remove it while claiming verbatim example transfer |
| D05 Persistence | Agent Ref, Checkpoint, Commit and Record structs; namespace, definition revision, tombstones; instance callbacks | Current persistence uses map envelopes and byte adapters; identity, load portability and uncertain-write checks now pass | Transfer the fixes and their regression tests. Preserve the explicit format policy. Treat the full new storage protocol as a separate change |
| D06 Cluster authority | Provider claims/leases/authority loss | DIST-03 allows concurrent activations; stale-write checks do not prevent earlier external work | User approved skipping only DIST-03 during plan review. Keep the capability limit explicit; implement authority and pass the test before claiming cluster-exclusive ownership |
| D07 Runtime pools | Separate Agent and Plugin pools; dependency-ordered root restart; fresh Plugin Init on replacement | Current PluginChild/PluginLifecycle and instance supervisor have a different shape | Test fresh committed state and cleanup first. Adopt an internal refactor only if examples retain their contracts |
| D08 Observation/errors | Semantic events only, no server timeline; closed error policy; new composed error structs | Runtime Inspection uses snapshots/debug events; examples use error-policy functions; current errors include raw reasons | Preserve public observations needed by examples; normalize errors and document changes. Do not remove inspection as a naming edit |
| D09 Runtime support | Project files state Elixir `~> 1.18`, OTP 27+ | Prepared source was tested with Elixir 1.20.3/OTP 29.0.5; dependencies also declare 1.18 | Test the declared floor before beta or explicitly raise it. Do not infer support from one local run |

Further design adoption is possible. For each selected decision, add a separate
commit specification after its dependent example group: public delta, affected
fixtures, positive/negative tests, state migration, and rollback boundary.
Keep a prepared donor copy of each affected example so the review can see
behavior changes beyond naming. The sequence in this folder assumes the
recommended choices above; it does not declare the other proposals implemented.

## Package compatibility

The inspected `jido_ai/lib` and `jido_browser/lib` contain 49 files that reference
core Agent, AgentServer, or related legacy APIs. Representative callers
are `jido_ai/lib/jido_ai/agent.ex`, `reasoning/react/strategy.ex`,
`directive/helpers.ex`, and `jido_browser/lib/jido_browser/plugin.ex`.

Their main risks are Strategy/StateOp removal, Plugin callback changes,
directive execution protocols, and result/inspection shapes. Keeping Agent
names does not make these callers compatible. Produce a package migration
table and at least one representative compilation/contract check before beta.
Do not rewrite the sibling packages as an unrecorded part of core migration.
The donor Factory tests use ReqLLM directly and therefore do not prove
`jido_ai` compatibility.
