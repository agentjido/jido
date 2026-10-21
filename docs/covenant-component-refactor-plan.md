# Covenant component refactor plan

Date: 2026-10-20
Status: Complete
Target: `agentjido/jido`, branch `release/v3`

## Purpose

Align Covenant components with current code ownership. Separate the generic
Plugin interface from each bundled Plugin. Split the current AgentServer
contract into smaller runtime components. Give durable Agent state and durable
Flow progress separate owners.

This plan does not approve an unrelated public API change. The hardening pass
can remove unused code and can refine runtime code when a component contract
or its tests prove the need. Other supported behavior stays unchanged unless a
listed removal has separate approval.

The approved component register is in
[`test/contract/COMPONENTS.md`](../test/contract/COMPONENTS.md). This plan
does not activate a component. A component becomes active only when it has an
obligation file and passing tagged contract tests.

## Hardening rules

1. Each public promise has one Covenant owner.
2. A component can test an integration result, but it must not claim another
   component's internal rules.
3. Mutation profiles contain behavior-bearing implementation modules. They do
   not contain data-only structs only to increase the module count.
4. Two active mutation profiles must not target the same module without a
   recorded reason.
5. Move or reduce code before adding adapters or compatibility wrappers.
6. Do not copy tests. Move a public case to its owner or keep a narrow
   integration case at the caller boundary.
7. Keep production-code line count neutral or lower in each extraction phase.
   Record and explain an increase before it is accepted.
8. Retire an old obligation in the same change that activates its replacement.
   The Covenant gate must stay complete at every step.
9. Do not create a full mutation baseline until the component shape is stable.
10. Keep `jido_action` and `jido_signal` behavior outside this package's
    Covenant components.

## Current package shape

### Current Covenant register

| Component | State | Active obligations | Mutation target modules | Main problem |
| --- | --- | ---: | ---: | --- |
| `jido.instance` | Active | 8 | 3 | The instance and Ref selection boundary is focused. |
| `jido.plugin` | Active | 8 | 9 | The generic boundary is focused and uses no bundled Plugin fixture. |
| `jido.agent` | Active | 21 | 13 | The model and authoring boundary is focused. |
| `jido.agent_evaluation` | Active | 10 | 6 | Pure evaluation has a separate owner. |
| `jido.signal_action` | Active | 7 | 1 | The combined Action and Signal value boundary is focused. |
| `jido.discovery` | Active | 5 | 1 | Read-only Action inventory has a separate owner. |
| `jido.telemetry` | Active | 8 | 7 | Best-effort observation has a separate owner. |
| `jido.error` | Active | 6 | 1 | Shared taxonomy, projection, and retry classification have a separate owner. |
| `jido.persistence` | Active | 15 | 11 | Shared records, snapshots, adapters, and storage operations have a separate owner. |
| `jido.agent_server` | Active | 37 | 1 | Core request, Turn, control, and observation behavior has a focused decision owner. |
| `jido.agent_server.activation` | Active | 11 | 3 | The local activation and recovery boundary is focused. |
| `jido.agent_server.effects` | Active | 11 | 2 | Post-commit effect admission, dispatch, and settlement have a separate owner. |
| `jido.agent_server.plugin_runtime` | Active | 12 | 2 | Generic live Plugin hosting has a separate owner. |
| `jido.agent_server.composition` | Active | 9 | 3 | Runtime child and connection resources have a separate owner. |
| `jido.agent_server.durable` | Active | 12 | 1 | Durable Agent state coordination has a separate owner. |
| `jido.agent_server.durable_turn` | Active | 11 | 3 | Durable Flow progress and waits have a separate owner. |
| `jido.plugin.audit` | Active | 4 | 2 | The bundled Audit Plugin is independent. |
| `jido.plugin.bus` | Active | 8 | 8 | The bundled Bus Plugin is independent. |
| `jido.plugin.heartbeat` | Active | 5 | 3 | The bundled Heartbeat Plugin is independent. |
| `jido.plugin.scheduler` | Active | 9 | 11 | The bundled Scheduler Plugin excludes durable business delivery. |
| `jido.plugin.sensor_manager` | Active | 8 | 8 | The bundled SensorManager Plugin is independent. |

The package has about 168 `Jido.*` modules. A module does not need a Covenant
owner only because it exists. All major public runtime areas now have an
independent Covenant owner.

### Current generic Plugin shape

`Jido.Plugin` defines one Plugin module with optional callbacks for three
current consumers:

| Consumer | Current callback group | Current implementation owner |
| --- | --- | --- |
| Agent | State declaration, preparation, Directive declaration, and reduction | `Jido.Agent.Plugin.*` |
| AgentServer | Admission, runtime startup, readiness, dispatch, commit, quiesce, and resume | `Jido.AgentServer.Plugin.*` |
| Persistence | Owned-state dump and load | `Jido.Persistence.Plugin.*` |

Generic interface code is under `lib/jido/plugin/` beside bundled products.
The current top-level directory therefore contains two different kinds of
code:

- Generic interface modules such as `Jido.Plugin`, `Manifest`, `Normalizer`,
  `Init`, and callback context values.
- Bundled implementations such as Audit, Bus, Heartbeat, Scheduler, and
  SensorManager.

The current Plugin design also contains Scheduler requirements. This makes the
generic interface document an owner of one bundled product. The code and tests
already show that Scheduler, Bus, SensorManager, Heartbeat, and Audit can change
independently.

The selected design required removal of Scheduler durable business delivery.
The source and focused tests no longer contain `Scheduler.Durable`,
`Delivery`, `Enqueue`, `Queue`, `Acknowledge`, or their business-delivery
behavior. The Scheduler Covenant keeps those features retired.

### Current AgentServer shape

At the start of this plan, `lib/jido/agent_server.ex` was 3,822 lines. Before
the final core extraction it was 3,716 lines. It is now 3,200 lines, and the
focused `Jido.AgentServer.Core` decision owner is 385 lines. The final
extraction therefore reduced the two-file total by 131 lines.

`Jido.AgentServer` remains the public API and shared `:gen_statem` coordinator.
It delegates core validation, admission, execution policy, ownership, queue,
terminal outcome, and failure-policy decisions to `Jido.AgentServer.Core`.
Other extracted owners handle effects, live Plugins, composition, durable
Agent state, and durable Flow progress.

The namespace also has about 22 supporting modules. Important existing seams
already include:

| Existing module | Current responsibility |
| --- | --- |
| `Jido.AgentServer.Core` | Core validation, admission, execution policy, ownership, outcomes, and failure decisions |
| `Jido.AgentServer.Supervisor` | Activation root, local checkpoint, worker and Plugin roots, child records |
| `Jido.AgentServer.Effects` | Post-commit effect admission, execution, and settlement |
| `Jido.AgentServer.Plugin.*` | Generic live Plugin callback execution |
| `Jido.AgentServer.CompositionRuntime` | Child relationship operations and composition admission |
| `Jido.AgentServer.TopologyRuntime` | Child and connection reconciliation |
| `Jido.AgentServer.TopologyBus` | Activation-owned logical Bus runtime |
| `Jido.AgentServer.Durable` | Durable Agent state coordination and decisions |
| `Jido.AgentServer.DurableTurn` | Durable Flow execution and recovery |
| `Jido.AgentServer.DurableTurn.CheckpointStore` | Runic workflow checkpoint storage bridge |
| `Jido.AgentServer.DurableTurn.WaitHost` | Durable wait input acceptance and receipts |

The final `jido.agent_server` mutation profile lists only
`Jido.AgentServer.Core`. Its 37 obligations cover only core request, Turn,
control, failure-policy, and bounded observation behavior. The public shared
coordinator is integration-tested across all AgentServer component suites.

### Current durable shapes

The code has three different recovery contracts:

1. **Local activation recovery.** The Supervisor keeps a canonical Agent and
   revision in activation-owned ETS. It can restore a replaced worker. This is
   not durable storage and does not survive activation loss.
2. **Durable AgentServer state.** `Jido.Persistence` stores the complete Agent record
   and revision. AgentServer coordinates create, restore, save-before-commit,
   hibernate, and authority loss.
3. **Durable Turn progress.** Runic checkpoints, Turn receipts, waits, and
   accepted wait inputs preserve Flow progress. This is not the same value as
   the Agent record revision.

The current AgentServer Covenant gives each shape a separate component and an
independent contract.

## Approved component map

```text
jido.agent_server
  -> jido.agent_evaluation
       -> jido.agent
       -> jido.plugin
  -> jido.agent_server.activation
       -> jido.instance
  -> jido.agent_server.effects
  -> jido.agent_server.plugin_runtime
       -> jido.plugin
  -> jido.agent_server.composition
  -> jido.agent_server.durable
       -> jido.persistence
  -> jido.agent_server.durable_turn
       -> jido.persistence

jido.signal_action
jido.discovery
jido.telemetry
jido.error

jido.plugin.audit -----------\
jido.plugin.bus --------------+
jido.plugin.heartbeat --------+-> jido.plugin
jido.plugin.scheduler --------+
jido.plugin.sensor_manager ---/
```

An arrow means that the first component uses the second component's public or
internal contract. It does not transfer ownership.

All component IDs start with `jido.`. Durable coordination stays under the
`jido.agent_server` boundary. There is no top-level `jido.durable` component.

## Approved supporting components

| Component | Owns | Excludes |
| --- | --- | --- |
| `jido.instance` | Jido instance supervision, namespace, options, Registry and Ref lookup, and instance wrappers | AgentServer Turn behavior |
| `jido.agent` | Agent definitions and instances, authoring, validation, logical topology, edits, shared authoring Registry, and deferred configuration | OTP runtime behavior |
| `jido.agent_evaluation` | Route selection, Agent Plugin preparation and reduction, Action and Flow execution, candidate validation, and returned Directives | OTP ownership, commit, dispatch, and persistence |
| `jido.persistence` | Records, identities, snapshots, adapter contracts, storage operations, revision checks, and Plugin state conversion | Runtime recovery decisions |
| `jido.signal_action` | Combined Signal and Action declaration, input conversion, and reply behavior | Signal routing and Action execution internals |
| `jido.discovery` | Read-only Action catalog and lookup | Authorization and Action execution |
| `jido.telemetry` | Events, safe metadata, metrics, tracing, logs, Debug support, and optional OpenTelemetry integration | Consumer behavior changes when observation fails |
| `jido.error` | Shared error taxonomy and stable common error codes | `Jido.Agent.Error` and `Jido.Plugin.Error`, which stay with their domain owners |

`Jido.Agent.Command` currently describes an AgentServer admission value. Keep
it with the runtime boundary unless a later refactor makes it a common
evaluation input.

## Approved Plugin components

### `jido.plugin`

Purpose: protect the generic Plugin declaration and callback interface.

Owns:

- Plugin identity and version.
- One Plugin module with optional callback groups.
- Manifest generation and validation.
- Option ownership and mapping.
- Callback discovery.
- Generic callback result forms.
- Directive type ownership declarations.
- Generic initialization and context values.
- Safe callback fault conversion.

Target modules:

- `Jido.Plugin`
- `Jido.Plugin.Manifest`
- `Jido.Plugin.Normalizer`
- `Jido.Plugin.Spec`
- `Jido.Plugin.Input`
- `Jido.Plugin.Init`
- `Jido.Plugin.SignalContext`
- `Jido.Plugin.DirectiveContext`
- `Jido.Plugin.Error`

Does not own:

- Agent preparation or reduction order.
- Live callback timing or process ownership.
- Persistence record meaning.
- Any bundled Plugin's business behavior.

### Consumer-owned Plugin behavior

| Component | Owned behavior | Main modules |
| --- | --- | --- |
| `jido.agent_evaluation` | Pure preparation, Plugin state transitions, Directive validation, and reduction order | `Jido.Agent.Plugin.*` |
| `jido.agent_server.plugin_runtime` | Live startup, readiness, admission, commit callbacks, dispatch, quiesce, resume | `Jido.AgentServer.Plugin.*` |
| `jido.persistence` | Dump and load of one Plugin-owned state value | `Jido.Persistence.Plugin.*` |

The generic component defines valid callback shapes. The consumer component
defines when the callback runs and what failure means.

### Bundled Plugin components

| Component | Module root | Owns | Excludes |
| --- | --- | --- | --- |
| `jido.plugin.audit` | `Jido.Plugin.Audit.*` | Record construction, retained order, limit, and state reduction | Generic callback rules |
| `jido.plugin.bus` | `Jido.Plugin.Bus.*` | Bus ownership, subscription, reconnect, delivery, and acknowledgement | Signal Bus internals owned by `jido_signal` |
| `jido.plugin.heartbeat` | `Jido.Plugin.Heartbeat.*` | Timer options, runtime ownership, and fresh tick Signals | General Plugin runtime rules |
| `jido.plugin.scheduler` | `Jido.Plugin.Scheduler.*` | Schedule definitions, cron rules, occurrences, generations, timer reconciliation, and future timer restore | Removed durable business delivery and acknowledgement |
| `jido.plugin.sensor_manager` | `Jido.Plugin.SensorManager.*` | Desired sensors, reconciliation, retries, and stale-work fencing | Sensor implementation behavior |

Do not create one `jido.plugins` component. The bundled Plugins have different
state, process, and delivery contracts.

## Approved AgentServer components

### `jido.agent_server`

Purpose: protect one transient serialized Turn worker.

Owns:

- Supported request input and context.
- Serial Turn admission.
- Queue limits and admission expiry.
- One active Turn.
- Turn deadline and cancellation.
- Runner ownership and cleanup.
- Candidate acceptance before commit coordination.
- Calls, casts, submit, await, and abandon.
- Failure policy.
- Bounded status and history.

Does not own:

- Activation-root recovery.
- Post-commit effect execution.
- Live Plugin processes.
- Child Agent resources.
- Durable storage.
- Durable Flow progress.

Core AgentServer result, 2026-10-20:

- 37 active obligations retain only core request, Turn, cancellation,
  failure-policy, control, and observation promises.
- Eight focused files contain 75 tests through the public AgentServer API and
  direct tests of focused core decisions.
- `Jido.AgentServer.Core` is the one mutation target. `Jido.AgentServer`
  remains the public API and shared state-machine coordinator.
- The full component profile checks 363 mutants: 360 are killed, 3 are
  invalid, and none survive or time out. The valid-mutant score is 100%.
- The public coordinator and focused core owner total 3,585 production lines,
  131 fewer than the 3,716-line coordinator before the final extraction.
- The complete Covenant gate passes 1,029 tests and all 225 active
  obligations across 21 components.
- The package suite and coverage run pass 1,301 tests with 577 exclusions.
  Package-only line coverage is 96.0%, above the 90% gate.

### `jido.agent_server.activation`

Purpose: protect the activation OTP root and local recovery.

Owns:

- Supervisor and worker identity.
- Worker and required Plugin root coupling.
- Startup and readiness publication.
- Registration guard behavior.
- Worker replacement.
- Cleanup barriers.
- Local checkpoint publication and conflict handling.
- Local checkpoint restore.
- Activation-owned owner, admission, idle, and child records.

The local checkpoint must stay distinct from `jido.agent_server.durable`.

The active mutation profile includes `Jido.AgentServer.Supervisor`,
`RegistrationGuard`, and `RegistryWorker`. Data-only child specifications do
not need mutation targets.

Activation result, 2026-10-20:

- 11 active obligations replace the 15 retired activation obligations.
- 45 focused tests cover startup, registration, readiness, local recovery,
  control records, idle behavior, and activation-owned child records.
- The full profile checks 215 mutants: 192 are killed, 17 classified survivors
  remain, 6 are invalid, and none time out. No survivor is unsorted.
- Plugin-root startup moved from `Jido.AgentServer.Supervisor` to
  `Jido.AgentServer.Plugin`; persistent lifetime helpers moved to
  `Jido.AgentServer.Durable`.
- The changed AgentServer owner files total four fewer production lines than
  their pre-extraction versions.

Effects result, 2026-10-20:

- 11 active obligations replace the 13 retired effect obligations. Old I102
  now keeps only runtime child lifetime behavior for composition.
- 34 focused tests cover complete admission, commit and reply order, failures,
  deadlines, ownership, Signal dispatch, safe error reports, runtime Agent
  Directives, and independent process start.
- The full profile checks 167 mutants: 136 are killed, 3 equivalent survivors
  remain, 28 are invalid, and none time out. No survivor is unsorted.
- Effect decisions and runtime Agent Directive work moved from the main server
  and the removed RuntimeDirectives module into Jido.AgentServer.Effects.
  Plugin Directive owner selection stays with Jido.AgentServer.Plugin.
- The changed effect owner files total 11 fewer production lines than their
  pre-extraction versions.
- The full Covenant gate passes 457 tests and all 176 active obligations.
- The package file set passes 1,239 tests with 573 exclusions. Line coverage
  remains 93.7%.

### `jido.agent_server.effects`

Purpose: protect post-commit work.

Owns:

- Complete effect-batch admission.
- Caller confirmation boundary.
- Ordered Directive execution.
- Effect deadline.
- Effect task ownership and cleanup.
- Stop-on-first-effect-failure behavior.
- Signal destinations and built-in runtime Directives.
- Post-commit failure reporting.

The active mutation profile includes `Jido.AgentServer.Effects` and
`Jido.Dispatch.Preparation`. Effect decisions and runtime Agent Directive work
are behind this owner. The main `Jido.AgentServer` state machine still owns
phase changes, timers, task startup, and replies.

### `jido.agent_server.plugin_runtime`

Purpose: protect generic live Plugin hosting.

Owns:

- Plugin root startup and identity.
- Ordered readiness.
- Admission callbacks.
- Required `after_commit` callbacks.
- Plugin-owned Directive dispatch.
- Callback deadlines, faults, and cleanup.
- Quiesce and resume callbacks.
- Runtime reconstruction from committed owned state and revision.

Target modules are `Jido.AgentServer.Plugin.*` and extracted live Plugin
coordination code. Bundled Plugin internals are excluded.

Plugin runtime result, 2026-10-20:

- 12 active obligations replace old AgentServer obligations I50-I62 and the
  Plugin-runtime part of I97.
- 65 focused tests cover runtime roots, readiness, live admission, commit
  callbacks, outbound Signal preparation, Directive dispatch, callback
  ownership, and safe live replacement.
- The full profile checks 229 mutants: 159 are killed, 31 classified survivors
  remain, 39 are invalid, and none time out. No survivor is unsorted.
- Live Plugin coordination moved from the main state machine into
  `Jido.AgentServer.Plugin` and `Jido.AgentServer.Plugin.Callbacks`. The main
  state machine retains phase changes, timers, task startup, and replies.
- Dead callback adapters and duplicate input guards were removed. The three
  changed production owner files total 26 fewer lines than before extraction.
- The full Covenant gate passes 472 tests and all 175 active obligations.
- The package file set passes 1,237 tests with 573 exclusions. Line coverage
  remains 93.7%.

### `jido.agent_server.composition`

Purpose: protect runtime resources described by accepted Agent data.

Owns:

- Owned and independent child activations.
- Child tags and reservations.
- Parent loss and adoption.
- Accepted topology member reconciliation.
- Activation-owned logical Buses.
- Connection delivery.
- Cleanup after accepted composition changes.

Target modules include `Jido.AgentServer.TopologyRuntime`,
`Jido.AgentServer.TopologyBus`, and the extracted `CompositionRuntime`.

Pure topology data validation remains in `jido.agent`.

Composition result, 2026-10-20:

- 9 active obligations replace old AgentServer obligations I65-I68, I95-I99,
  and the child-lifetime part of I102.
- 41 focused tests cover child ownership, adoption, accepted composition,
  member recovery, readiness, connection delivery, local Buses, and runtime
  child restart policy.
- The full profile checks 300 mutants: 260 are killed, 22 classified survivors
  remain, 18 are invalid, and none time out. No survivor is unsorted.
- Child behavior moved from the main state machine into
  `Jido.AgentServer.CompositionRuntime`. Topology reconciliation remains in
  `TopologyRuntime`, and local Bus ownership remains in `TopologyBus`.
- The five changed composition owner files total 10 fewer production lines
  than their pre-extraction versions. `Jido.AgentServer` is 272 lines smaller.
- The full Covenant gate passes 475 tests and all 174 active obligations.
- The package file set passes 1,240 tests with 573 exclusions. Line coverage is
  94.0%.

### `jido.agent_server.durable`

Purpose: protect persistence-backed AgentServer coordination.

Owns:

- Explicit create and restore policy.
- Revision-zero creation before readiness.
- Required save before local publication and caller success.
- Expected-revision use.
- Separate storage deadline.
- Conflict and indeterminate-write authority loss.
- Durable reload before Plugin reconstruction.
- Portable Agent and Plugin checkpoint conversion use.
- Hibernate and persistent idle policy.
- Atomic live snapshot.
- Persisted definition upgrade coordination.

Does not own:

- Record formats, keys, or adapter result classification. These belong to
  `jido.persistence`.
- Local worker checkpoints. These belong to
  `jido.agent_server.activation`.
- Flow graph progress. This belongs to `jido.agent_server.durable_turn`.

The public entry points can remain on `Jido.AgentServer` and `Jido`. A new
public Server type is not required. `Jido.AgentServer.Durable.*` can be an internal
coordination namespace.

Durable result, 2026-10-20:

- 12 active obligations replace AgentServer I77-I83, I91-I93, I100, and I101.
- 48 focused tests cover configuration, create, restore, required commit,
  authority loss, portability, hibernation, idle hibernation, snapshots, and
  upgrades.
- The full profile checks 72 mutants: 64 are killed and 8 classified survivors
  remain. None are invalid, timed out, or unsorted.
- Durable decisions moved into `Jido.AgentServer.Durable`. Pending Flow receipt
  validation moved to the existing `Jido.AgentServer.DurableTurn` owner.
- The three changed production files total 20 fewer lines than before this
  extraction. `Jido.AgentServer` is 107 lines smaller.
- The full Covenant gate passes 478 tests and all 174 active obligations.
- The package file set passes 1,243 tests with 573 exclusions. Core package
  line coverage is 94.1%.

### `jido.agent_server.durable_turn`

Purpose: protect persistent Flow execution progress.

Owns:

- Durable Turn acceptance receipt.
- Stable execution identity.
- Runic workflow checkpoint confirmation.
- Saved step progress.
- Suspension and recovery.
- Open wait identity.
- Accepted wait input and duplicate handling.
- `deliver_wait/4` behavior.
- Deadlines across worker recovery.
- Terminal and cancellation receipts.
- No replay of already confirmed progress.

Initial target modules:

- Keep `Jido.AgentServer.DurableTurn` as the coordination owner.
- Rename `Jido.AgentServer.CheckpointStore` to
  `Jido.AgentServer.DurableTurn.CheckpointStore`.
- Rename `Jido.AgentServer.WaitHost` to `Jido.AgentServer.DurableTurn.WaitHost`.

These modules are internal today. Do not add compatibility delegates unless a
real external caller is found.

Durable Turn result, 2026-10-20:

- 11 active obligations define accepted Flow receipts, checkpoint authority,
  recovery, waits, terminal results, abort closure, and the durable capability
  boundary.
- 61 focused tests cover the three internal durable Turn modules.
- `CheckpointStore` and `WaitHost` moved under
  `Jido.AgentServer.DurableTurn` without compatibility delegates.
- The four changed production files total 5 fewer lines than before this
  extraction.
- The full mutation run tested 238 mutants: 217 were killed, 13 classified
  survivors remain, 8 were invalid, and none timed out or remained unsorted.
  The score is 94.3%.
- The full Covenant gate passes 1,029 tests and all 225 active obligations.
- The package file set passes 1,301 tests with 577 exclusions. Core package
  line coverage is 96.0%.

## Current AgentServer obligation migration

The current obligations are often compound. Split them when two approved
owners control different results.

| Current obligation area | Approved owner | Required action |
| --- | --- | --- |
| I1-I8, I10-I31, I33-I34 | `jido.agent_server` | Retain core request, Turn, cancellation, failure, and observation timing rules. Split safe metadata shape to observability if needed. |
| I9, I32, I39-I49 | `jido.agent_server.effects` | Moved and retired. Effects I1-I11 own batch admission, reply timing, dispatch, deadlines, post-commit failure, runtime Agent Directive handoff, and independent process start. |
| I35-I38, I63-I64, I69, I72-I76, I88-I90 | `jido.agent_server.activation` | Moved and retired. Replacement activation obligations I1-I11 own identity, selected-instance ownership, fixed defaults, readiness, recovery, local checkpoints, control, idle behavior, and activation child records. |
| I70-I71 | `jido.instance` | Already moved stable Ref identity and Ref routing to `jido.instance.I6-I8`. |
| I50-I62 and the Plugin-runtime part of I97 | `jido.agent_server.plugin_runtime` | Moved and retired. Plugin runtime I1-I12 own live roots, callbacks, and safe replacement. |
| I65-I68, I95-I99 | `jido.agent_server.composition` | Moved and retired. Composition I1-I9 own child relationships, topology resources, accepted composition, connection delivery, and runtime child lifetime. |
| I77-I83, I91-I93, I100 | `jido.agent_server.durable` | Move durable create, save, restore, hibernate, and snapshot promises. Split the default nonpersistent idle-stop rule back to activation. |
| I84-I87, part of I94 | `jido.agent_server` | Keep general admission control and control safety. Move persistence-specific configuration to AgentServer durable coordination. |
| I101 | `jido.agent_server.durable` and `jido.agent_server.composition` | Split durable upgrade commit from target validation and resource reconciliation. |
| I102 | `jido.agent_server.effects` and `jido.agent_server.composition` | Split effect execution from child-resource ownership. |
| Durable Flow behavior not represented by a complete current range | `jido.agent_server.durable_turn` | Create new obligations from current durable Turn and wait behavior. Do not infer credit from general AgentServer obligations. |

## Target code shape

The target is not one wrapper per Covenant component. Move behavior into the
existing or new owner module and delete the old implementation from
`Jido.AgentServer`.

Recommended shape:

```text
lib/jido/
  agent_server.ex                    # public API and core state machine
  agent_server/
    activation.ex                    # activation policy and local recovery
    supervisor.ex
    effects.ex                       # post-commit effect loop
    plugin.ex                        # live generic Plugin coordination
    plugin/callbacks.ex              # callback adapters and validation
    composition_runtime.ex
    topology_runtime.ex
    topology_bus.ex
    durable/
      commit.ex                      # save-before-publication coordination
      recovery.ex                    # create, restore, and durable reload
      control.ex                     # hibernate and persistent idle policy
      upgrade.ex                     # persisted upgrade coordination
    durable_turn.ex                  # durable Flow coordination
    durable_turn/
      checkpoint_store.ex
      wait_host.ex

  plugin/                            # generic Plugin interface
    ...
    audit/
    bus/
    heartbeat/
    scheduler/
    sensor_manager/
```

Use this as an ownership map, not a required file-count target. Combine a new
module when it only forwards calls. Prefer fewer modules and less code.

## Refactor plan

### Phase 0: approve names and limits

- [x] Approve the component names in the component register.
- [x] Confirm that `Jido.AgentServer.Durable.*` is internal and that public calls
      remain on `Jido.AgentServer` and `Jido`.
- [x] Confirm that durable Turn progress is a separate component from durable
      Agent state.
- [x] Confirm that every bundled Plugin has its own component.
- [x] Confirm that Scheduler durable business delivery is removed before the
      Scheduler Covenant becomes active.
- [x] Confirm that current supported public behavior is preserved during code
      extraction.
- [x] Record the current AgentServer name and remove the obsolete prototype
      decisions and mutation baseline.

Exit condition: the boundary map and removal scope have user approval.

### Phase 1: create a migration ledger

- [x] Add one row for every current `jido.agent_server` obligation.
- [x] Give each row one target component and target obligation ID.
- [x] Mark compound obligations that must split.
- [x] Map each existing contract test to the target obligation.
- [x] Map each behavior-bearing module to one mutation profile.
- [x] List modules that remain unit-test-only and state why.
- [x] List public functions whose owner changes but whose API does not change.

Exit condition: no current obligation, contract test, or behavior-bearing
runtime module is unassigned.

### Phase 2: split generic Plugin Covenant ownership

- [x] Write `jido.plugin` obligations for declarations, manifests, options,
      callback groups, callback results, Codec behavior, and error containment.
- [x] Use generic test Plugins. Do not use Scheduler, Bus, SensorManager,
      Heartbeat, or Audit as generic contract fixtures.
- [x] Create focused contract tests under `test/contract/jido.plugin/core/`.
- [x] Move Agent preparation and reduction obligations to
      `jido.agent_evaluation`.
- [x] Keep live callback timing in the future Plugin runtime component.
- [x] Keep dump and load execution in the future persistence component.
- [x] Activate the generic mutation profile only after its baseline tests pass.
- [x] Run a mutation-profile resolution check.

Exit condition: the generic Plugin component can pass without loading a
bundled Plugin.

### Phase 3: remove selected Scheduler durable delivery

- [x] Confirm saved-definition compatibility for old delivery fields.
- [x] Remove `Scheduler.Durable`, `Delivery`, `Enqueue`, `Queue`,
      `Acknowledge`, and `Signal.Enqueue` where the selected design requires.
- [x] Remove `delivery: :durable`, `admit_occurrence/2`, `acknowledge/1`,
      delivery retry options, and pending-delivery state.
- [x] Remove or rewrite tests that promise business acknowledgement or pending
      delivery replay.
- [x] Preserve schedule definitions, cron behavior, one-shot timers, recurring
      future timers, generation identity, and occurrence metadata.
- [x] Update guides and examples in the same change.

Exit condition: Scheduler source and tests contain no removed delivery promise.

### Phase 4: add bundled Plugin components

Do one bundled Plugin at a time. Start with the smallest component and finish
Scheduler last.

- [x] Add `jido.plugin.audit`.
- [x] Add `jido.plugin.heartbeat`.
- [x] Add `jido.plugin.sensor_manager`.
- [x] Add `jido.plugin.bus`.
- [x] Add `jido.plugin.scheduler` after Phase 3.
- [x] For each component, select only its module root and behavior-bearing
      helpers for mutation.
- [x] Keep generic callback failures in `jido.plugin` or the live consumer.
- [x] Keep external `jido_signal` Bus behavior outside `jido.plugin.bus`.

Exit condition: each bundled Plugin can change without changing generic Plugin
obligations.

### Phase 5: separate AgentServer test ownership

Before moving runtime code, reorganize public cases by target owner.

- [x] Create the activation contract test folder.
- [x] Create the effects and Plugin runtime contract test folders.
- [x] Create the composition contract test folder.
- [x] Create the AgentServer durable coordination contract test folder.
- [x] Create the core AgentServer contract test folder.
- [x] Create the durable Turn coordination contract test folder.
- [x] Move or extract activation cases without copying the old suites.
- [x] Keep shared AgentServer fixtures in one neutral support module.
- [x] Remove Plugin product fixtures from generic Plugin runtime tests.
- [x] Keep one observable Plugin-runtime handoff in composition tests.
- [x] Keep the old obligation tags active until each target component is ready.

Exit condition: each existing case has one approved owner, and the complete
existing suite still passes.

### Phase 6: extract existing low-risk runtime seams

- [x] Move nested `CompositionRuntime` into its own file without changing
      behavior.
- [x] Move effect-loop functions from `Jido.AgentServer` into one effect owner.
- [x] Move live Plugin coordination into the existing
      `Jido.AgentServer.Plugin.*` area.
- [x] Move child and topology reconciliation behind the composition owner.
- [x] Remove moved functions from `Jido.AgentServer`; do not leave forwarding
      private functions.
- [x] Keep only thin public delegates when the public API requires them.
- [x] Check production-code line count after each extraction.

Exit condition: effects, live Plugin hosting, and composition have separate
behavior-bearing modules and no duplicate implementation.

### Phase 7: separate activation from core Turn work

- [x] Isolate activation startup, readiness, registration, worker replacement,
      local checkpoint, and recovery policy.
- [x] Keep `Jido.AgentServer` focused on the active Turn state machine.
- [x] Move activation-owned metadata access behind the activation owner.
- [x] Keep local checkpoint data free of portable or durable claims.
- [x] Preserve one-for-all recovery and cleanup barriers.
- [x] Preserve current public PID and name behavior.

Exit condition: memory-only worker recovery can be tested without a persistence
adapter.

### Phase 8: extract AgentServer durable coordination

- [x] Move create and restore selection out of the core state machine.
- [x] Move required save construction and result classification behind
      `Jido.AgentServer.Durable`; keep task ownership in the state machine.
- [x] Move durable reload-before-readiness behavior behind the durable owner.
- [x] Move hibernate and persistent idle save decisions behind the durable owner.
- [x] Move durable snapshot and upgrade coordination behind the durable owner.
- [x] Keep `Jido.Persistence` as the only owner of records, keys, CAS, and
      adapter result classification.
- [x] Keep the core server responsible only for applying the returned durable
      decision to its live state transition.
- [x] Delete duplicate timeout, revision, and authority checks from the core
      module after the extraction.

Exit condition: core AgentServer tests pass with persistence disabled, and
AgentServer durable tests exercise storage coordination through the public
Server API.

### Phase 9: extract AgentServer durable Turn coordination

- [x] Place the three current internal durable Turn modules under the approved
      namespace.
- [x] Move durable Flow coordination out of the core AgentServer helper set.
- [x] Define obligations for acceptance, checkpoint confirmation, waits,
      recovery, deadlines, cancellation, and terminal receipts.
- [x] Move current durable Turn, Flow wait, checkpoint store, and wait-host
      tests into this owner.
- [x] Add integration cases for the handoff between durable Agent save and
      durable Flow progress.
- [x] Confirm that Agent revision and Flow checkpoint identity cannot be
      confused.
- [x] Confirm that ordinary Directives remain non-durable.

Exit condition: durable Turn tests can identify their state and failure rules
without using general AgentServer obligations.

### Phase 10: activate the split Covenant components

Activate one component per change:

1. `jido.agent_server.activation`
2. `jido.agent_server.effects`
3. `jido.agent_server.plugin_runtime`
4. `jido.agent_server.composition`
5. `jido.agent_server.durable`
6. `jido.agent_server.durable_turn`
7. `jido.agent_server`

For each activation:

- [x] Add the obligation file and focused contract tests.
- [x] Add the non-overlapping mutation module profile.
- [x] Map each replaced current `jido.agent_server` obligation to its final
      owner. Retire only the obligations that move to another component.
- [x] Regenerate Covenant coverage.
- [x] Run one mutation-profile resolution check.
- [x] Record that the check is focused unless the full profile completed.

Completed for `jido.agent_server.activation`:

- [x] Added the obligation file and focused contract tests.
- [x] Added a non-overlapping three-module mutation profile.
- [x] Mapped and retired old obligations I35-I38, I63-I64, I69, I72-I76, and
      I88-I90.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 215-mutant profile with no unsorted survivor.
- [x] Recorded the check as a full component result.

Completed for `jido.agent_server.effects`:

- [x] Added the obligation file and five focused contract test files.
- [x] Added a non-overlapping two-module mutation profile.
- [x] Mapped and retired old obligations I9, I32, and I39-I49. Split the
      effect part from old I102 and kept its child-lifetime part active.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 167-mutant profile with no unsorted survivor.
- [x] Recorded the check as a full component result.

Completed for `jido.agent_server.plugin_runtime`:

- [x] Added the obligation file and six focused contract test files.
- [x] Added a non-overlapping two-module mutation profile.
- [x] Mapped and retired old obligations I50-I62 and the Plugin-runtime part of
      I97.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 229-mutant profile with no unsorted survivor.
- [x] Recorded the check as a full component result.

Completed for `jido.agent_server.composition`:

- [x] Added the obligation file and five focused contract test files.
- [x] Added a non-overlapping three-module mutation profile.
- [x] Mapped and retired old obligations I65-I68, I95-I99, and I102.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 300-mutant profile with no unsorted survivor.
- [x] Recorded the check as a full component result.

Completed for `jido.agent_server.durable`:

- [x] Added the obligation file and three focused contract test files.
- [x] Added a non-overlapping one-module mutation profile.
- [x] Mapped and retired old obligations I77-I83, I91-I93, I100, and I101.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 72-mutant profile with no unsorted survivor.
- [x] Recorded the check as a full component result.

Completed for `jido.agent_server.durable_turn`:

- [x] Added the obligation file and five focused contract test files.
- [x] Added a non-overlapping three-module mutation profile.
- [x] Defined new obligations because the root contract had no complete
      durable Flow obligation range to retire.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 238-mutant profile with no unsorted survivor.
- [x] Recorded the check as a full component result.

Completed for `jido.agent_server`:

- [x] Kept 37 core obligations and moved all other behavior to the approved
      AgentServer subcomponents.
- [x] Added eight focused contract test files with 75 tests.
- [x] Added the non-overlapping `Jido.AgentServer.Core` mutation profile.
- [x] Regenerated complete Covenant coverage: 1,029 tests and 225 obligations.
- [x] Completed the full component mutation profile: 360 killed valid mutants,
      3 invalid mutants, no survivor, and no timeout.
- [x] Recorded the public coordinator and focused decision-owner split.

Completed for supporting component `jido.instance`:

- [x] Kept 8 obligations focused on instance configuration, supervision,
      namespace ownership, lifecycle selection, and stable Ref routing.
- [x] Kept one non-overlapping three-module mutation profile and 55 focused
      contract tests.
- [x] Replaced a timed-out `submit/4` options mutation with an immediate
      contract failure and retained four documented first-boot ETS limits.
- [x] Completed the full 247-mutant profile with 224 killed mutants,
      18 classified survivors, 5 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for supporting component `jido.plugin`:

- [x] Kept 8 obligations focused on generic Plugin declaration, manifests,
      normalization, callback shapes, fault conversion, and narrow values.
- [x] Expanded the mutation profile to all 9 generic behavior and value
      modules without adding a bundled Plugin implementation.
- [x] Aligned 27 contract tests with complete context fields, defaults,
      version bounds, and required normalized Spec keys.
- [x] Regenerated complete Covenant coverage across all 225 obligations.
- [x] Completed the full 565-mutant profile with 422 killed mutants,
      74 classified survivors, 69 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for supporting component `jido.agent`:

- [x] Kept 21 obligations focused on Agent data, authoring, validation,
      topology, edits, deferred configuration, and shared Registry behavior.
- [x] Reduced the mutation profile to 13 behavior-owning modules and moved
      route evaluation and checkpoint callback containment to their owners.
- [x] Aligned 148 contract tests with the component boundary and regenerated
      complete Covenant coverage.
- [x] Completed the full 1,534-mutant profile with 1,364 killed mutants,
      101 classified survivors, 1 classified timeout, 68 invalid mutations,
      and no unsorted mutant.

Completed for supporting component `jido.agent_evaluation`:

- [x] Kept 10 obligations focused on route selection, Plugin preparation,
      execution, candidate validation, reduction, and returned Directives.
- [x] Added `Jido.Agent.Route` to the six-module mutation profile and kept
      Agent authoring normalization with `jido.agent`.
- [x] Aligned 14 contract tests with the component boundary and regenerated
      complete Covenant coverage.
- [x] Completed the full 364-mutant profile with 233 killed mutants,
      84 classified survivors, 47 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for supporting component `jido.persistence`:

- [x] Added 15 obligations and 11 focused contract test files.
- [x] Added a non-overlapping eleven-module mutation profile for shared
      persistence behavior.
- [x] Kept backend-specific behavior and live recovery policy with their
      separate owners.
- [x] Moved Agent checkpoint callback failure tests from the broad Agent suite
      into the persistence boundary and reduced the test code by 67 lines.
- [x] Regenerated complete Covenant coverage across all 225 obligations.
- [x] Completed the full 708-mutant profile with 627 killed mutants,
      30 classified survivors, 51 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for supporting component `jido.signal_action`:

- [x] Added 7 obligations and 10 focused contract tests.
- [x] Kept Action execution, Signal routing, Agent route authoring, and
      AgentServer commit timing with their separate owners.
- [x] Added the non-overlapping `Jido.SignalAction` mutation profile.
- [x] Removed duplicate reply validation and moved Agent route type lowering
      to the Agent DSL owner.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 112-mutant profile with 78 killed mutants,
      3 classified message-only survivors, 31 invalid mutations, and no
      timeout.

Completed for supporting component `jido.discovery`:

- [x] Added 5 obligations and 7 focused contract tests.
- [x] Kept Agent route discovery and product permission policy with their
      separate owners.
- [x] Added the non-overlapping `Jido.Discovery` mutation profile.
- [x] Removed duplicate lookup and Instruction checks, unused slug-collision
      policy, and a stale guide reference.
- [x] Reduced production Discovery code by 13 lines.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 128-mutant profile with 126 killed mutants,
      2 classified logging-only survivors, no invalid mutation, and no
      timeout.

Completed for supporting component `jido.telemetry`:

- [x] Added 8 obligations and 7 focused contract test files with 86 tests.
- [x] Kept observed runtime operations, reporter configuration, SDK startup,
      sampling, export, and durable audit with their separate owners.
- [x] Added one non-overlapping profile for the 7 Telemetry, Debug, and tracing
      modules.
- [x] Reduced the component production modules by 44 lines.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 714-mutant profile with 657 killed mutants,
      16 classified equivalent survivors, 41 invalid mutations, and no
      timeout.

Completed for supporting component `jido.error`:

- [x] Added 6 obligations and 3 focused contract test files with 69 tests.
- [x] Kept Agent and Plugin errors, domain failure conversion,
      adjacent-package errors, and runtime retry policy with their separate
      owners.
- [x] Added the non-overlapping `Jido.Error` mutation profile.
- [x] Registered the 3 existing Config codes, removed the unused message
      extractor, removed dead retry-classification code, and contained Inspect
      failures without local stacktrace leakage.
- [x] Reduced `Jido.Error` by 54 lines and the focused tests by 99 lines.
- [x] Regenerated complete Covenant coverage.
- [x] Completed the full 301-mutant profile with 288 killed mutants,
      13 invalid mutations, no survivor, and no timeout.

Completed for bundled component `jido.plugin.audit`:

- [x] Kept 4 obligations and 6 focused contract tests for portable record
      construction, declaration, bounded retention, ordering, and filtering.
- [x] Kept the non-overlapping two-module mutation profile.
- [x] Confirmed that no generic Plugin, Agent evaluation, commit, or
      persistence behavior remains in this component.
- [x] Completed the full 61-mutant profile with 46 killed mutants,
      9 classified survivors, 6 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for bundled component `jido.plugin.heartbeat`:

- [x] Kept 5 obligations and 5 focused contract tests for timer options,
      runtime ownership, and fresh default and custom tick Signals.
- [x] Kept the non-overlapping three-module profile; the declarative Tick
      Signal module has no mutable body.
- [x] Confirmed that each contract test has a unique mutation kill.
- [x] Completed the full 49-mutant profile with all 49 mutants killed and no
      survivor, invalid mutation, or timeout.

Completed for bundled component `jido.plugin.sensor_manager`:

- [x] Kept 8 obligations and 11 focused contract tests for portable desired
      state, exact reconciliation, revision fencing, recovery, retry, and
      runtime failure containment.
- [x] Kept the non-overlapping eight-module mutation profile.
- [x] Confirmed that sensor implementation behavior and generic Plugin timing
      remain outside this component.
- [x] Completed the full 192-mutant profile with 158 killed mutants,
      13 classified survivors, 21 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for bundled component `jido.plugin.bus`:

- [x] Kept 8 obligations and 16 focused contract tests for local declaration,
      Bus ownership, subscription, reconnect, delivery, acknowledgement,
      retry, reattachment, and worker lifetime.
- [x] Kept Signal Bus routing, storage, replay, cursor, and subscription
      internals outside this package-owned component.
- [x] Replaced a timed-out pending-worker cleanup mutation with a direct
      contract failure.
- [x] Completed the full 193-mutant profile with 172 killed mutants,
      7 classified survivors, 14 invalid mutations, no timeout, and no
      unsorted mutant.

Completed for bundled component `jido.plugin.scheduler`:

- [x] Kept 9 obligations and 24 focused contract tests for definitions,
      static authoring, timer ownership, reconciliation, occurrence identity,
      recovery, retry, clocks, and readiness.
- [x] Added the two static DSL modules to the non-overlapping eleven-module
      profile because obligation I3 owns their declaration and lowering.
- [x] Added one compile-time entity-target invariant so an invalid Spark
      declaration fails synchronously instead of terminating the mutation
      worker.
- [x] Refined I3 to prove one authoring source, defaults, exact timing forms,
      UTC defaulting, and schedule-scoped route errors.
- [x] Completed the full 476-mutant profile with 381 killed mutants,
      67 classified survivors, 28 invalid mutations, no timeout, and no
      unsorted mutant.

After the final migration:

- [x] Keep only core turn-state obligations in `jido.agent_server`.
- [x] Keep a concise ID migration record.
- [x] Remove the stale prototype baseline instead of carrying historical
      mutation claims into the new components.
- [x] Rename current contract documentation from prototype terminology.

Exit condition: each active obligation and mutation profile has one final
component owner.

### Phase 11: final hardening pass

- [x] Search for stale component IDs, module names, and deleted Scheduler APIs.
- [x] Remove unused fixtures, helpers, test-only compatibility paths, and
      duplicate validation.
- [x] Confirm that production code has not grown without an approved reason.
- [x] Run format, warning-free compile, strict Credo, contract tests, authoring
      tests, full package tests, property tests, and documentation build.
- [x] Run focused mutation checks for every new profile.
- [x] Run full mutation analysis only after all profiles and source locations
      are stable.
- [x] Publish no full mutation score from an old source shape.

Final verification, 2026-10-20:

- Formatting, warning-free compilation, strict Credo, and documentation build
  pass.
- The complete Covenant gate passes 1,029 tests and 225 of 225 active
  obligations across 21 components.
- The package suite passes 1,301 tests with 577 exclusions. The separate
  authoring and property suites pass 73 and 41 tests.
- Package-only line coverage is 96.0%, above the 90% gate.
- All active component mutation profiles have no unsorted survivor or timeout.
- Production code in the final hardening diff removes two lines and adds none.

Exit condition: component ownership, tests, module profiles, and documentation
all describe the same code.

## Test handoff rules

Use these rules when a behavior crosses components:

| Handoff | Upstream owner proves | Downstream owner proves |
| --- | --- | --- |
| Generic Plugin to Agent evaluation | Callback declaration and result shape | Preparation and reduction order |
| Generic Plugin to live runtime | Runtime callback availability and shape | Timing, process ownership, deadline, and failure result |
| Persistence to AgentServer durable coordination | Record and CAS result | Commit, stop, restore, or hibernate response |
| Agent evaluation to effects | Valid ordered Directive batch | Post-commit dispatch and settlement |
| Agent composition to runtime composition | Valid accepted data and Diff | Resource reconciliation and cleanup |
| AgentServer durable state to durable Turn | Authoritative Agent revision | Workflow progress, wait, and receipt identity |
| Instance to activation | Namespace and Ref resolution | Activation startup, readiness, and lifetime |

Do not tag one test for both sides only to produce coverage. Use two narrow
assertions when each owner has a different failure rule.

## Per-phase verification

Run checks inside `jido`.

Minimum checks for documentation or Covenant-only changes:

```sh
mix format --check-formatted
mix test.contract
```

Minimum checks for code extraction:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict --only warning
mix test.contract
mix test
```

Run component-focused tests before the full package suite. Run property,
service, or peer tests when the changed owner uses those boundaries.

## Approved decisions

These decisions define the approved scaffold:

1. Use `jido.plugin` only for the generic interface.
2. Give Audit, Bus, Heartbeat, Scheduler, and SensorManager separate Covenant
   components.
3. Remove Scheduler durable business delivery before activating its component.
4. Split AgentServer into core, activation, effects, Plugin runtime, and
   composition components.
5. Use `jido.agent_server.durable` for persistent Agent activation coordination.
6. Use `jido.agent_server.durable_turn` for persistent Flow progress and waits.
7. Keep AgentServer durable coordination as an internal owner behind the
   current public APIs.
8. Keep local activation checkpoints outside the AgentServer durable contract.
9. Preserve current public behavior during extraction unless a separate
   removal is approved.
10. Require neutral or lower production-code line count for the refactor.

## Definition of done

- Generic Plugin tests do not depend on any bundled Plugin.
- Every bundled Plugin has one independent Covenant owner or a recorded reason
  to remain unit-test-only.
- Core AgentServer tests run with persistence and durable Flow support disabled.
- Local activation recovery, durable Agent state, and durable Flow progress
  have separate obligations and mutation profiles.
- `Jido.AgentServer` no longer contains the full implementation for effects,
  live Plugin hosting, composition, durable save coordination, and durable Flow
  progress.
- No new public Server type or compatibility wrapper exists without a proven
  caller need.
- `jido.agent_server` contains only core turn-state obligations.
- Covenant coverage, module profiles, guides, and current code agree.
- The full package checks pass.
- The production-code line count is neutral or lower, unless the user approves
  a documented exception.
