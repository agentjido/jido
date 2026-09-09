> Seam alignment plan. This document is pending approval.

# Jido instance alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `0250817cd1dea6c34181fa8fd6e9ef9faa2d33a7` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md),
  [07 Persistence](../07_persistence/alignment.md), and
  [08 Agent Server](../08_agent-server/alignment.md). All were used as pending
  draft prerequisites.
- Related inputs: [02 Agent authoring](../02_agent-authoring/design.md) and
  [04 Turn evaluation](../04_turn-evaluation/design.md).
- Alignment state: `Blocked` on pending prerequisite and instance decisions.
- Approved decisions: None.

The alignment state is execution status. It is not document approval. This file
defines outcomes and gates. It is not the formal implementation plan.

## Inputs and evidence

### Design inputs

- [Jido V3 vision](../VISION.md): defines Jido as a composable library, keeps
  application supervision under developer control, and places cluster,
  transport, deployment, and control-plane policy outside core.
- [Overview design](../00_overview/design.md): keeps the local runtime,
  same-instance runtime-checkpoint recovery, public PID APIs during migration,
  stable identity as a target, and current observation paths.
- [Package-boundary design](../90_package-boundaries/design.md): keeps the Jido
  instance in core and keeps general durable, cluster, and transport services
  outside core.
- [Errors design](../12_errors-and-contracts/design.md): requires owner-defined
  errors while permitting documented OTP and compatibility protocol values.
- [Agent design](../01_agent/design.md) and
  [Agent authoring design](../02_agent-authoring/design.md): keep Agent state
  and construction outside the instance. The authoring input keeps generated
  live helpers tied to public Agent Server calls.
- [Identity design](../03_agent-identity/design.md): owns the proposed
  `{namespace, partition, id}` Ref and assigns namespace binding to this seam.
- [Turn design](../04_turn-evaluation/design.md),
  [Plugin design](../05_plugins/design.md), and
  [commit design](../06_commit-and-effects/design.md): keep selection, Plugin
  data, commit, and effects outside instance policy.
- [Persistence design](../07_persistence/design.md): keeps a binary adapter,
  per-Agent persistence selection, and lifecycle meaning outside this seam.
- [Agent Server design](../08_agent-server/design.md): keeps direct PID and name
  APIs and assigns additive Ref-first resolution to this seam.
- [Target design](design.md): defines the recommended instance target.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido.ex:8-68` | Public module documentation presents an application-supervised instance, ID lookup, PID return, and direct Agent commands. |
| `lib/jido.ex:70-142` | `use Jido` requires `:otp_app`, accepts compile-time persistence, generates OTP functions, merges application config with runtime overrides, and makes `config/1` overridable. |
| `lib/jido.ex:144-229` | A generated module exposes lifecycle, local-name, debug, and bounded recent-event helpers. |
| `lib/jido.ex:236-316` | `Jido.Default` supports idempotent script and Livebook startup. The package does not start it automatically. |
| `lib/jido.ex:318-370` | A plain instance requires an atom name and starts Task Supervisor, Registry, Runtime Store, Spawn Registry, and Agent Dynamic Supervisor under `:one_for_one`. |
| `lib/jido.ex:380-425` | Local service names derive from the instance atom. Partition keys accept any term. |
| `lib/jido.ex:431-599` | Startup returns a PID. ID and partition lookup, list, count, duplicate registration, and Agent-supervisor ownership are current contracts. |
| `lib/jido.ex:601-684` | Parent binding, hibernate, and thaw are public instance functions. Thaw uses required restore. |
| `lib/jido.ex:699-740` | PID and Server-reference lifecycle calls verify instance and partition ownership before they act. |
| `lib/jido/application.ex:1-9` | The package application sets up Telemetry and starts only an empty `Jido.Supervisor`. |
| `lib/jido/runtime_store.ex:1-23,57-78` | The instance Supervisor owns an ETS table that survives Runtime Store worker restart but not full instance stop. |
| `lib/jido/agent_server.ex:82-348` | Agent Server has a documented public PID and name API for command, control, inspection, lifecycle, lookup, and debug. |
| `lib/jido/agent_server/options.ex:4-136,377-405` | Agent options use Zoi. An explicit per-Agent persistence value overrides or disables the instance default. |
| `lib/jido/agent_server/runtime_checkpoint.ex:8-50` | A named nonpersistent Server restores the latest in-instance commit after abnormal restart. |
| `lib/jido/agent_server/plugin_lifecycle.ex:101-198` | Current Plugin runtime wrappers start in the Agent Dynamic Supervisor and register in the instance Registry. |
| `lib/jido/persistence.ex:27-57,153-231` | Instance persistence declarations are normalized and validated when consumed. Durable keys use instance atom, Agent module, partition, and ID. |

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/instance_test.exs:95-128` | Application config merges before runtime overrides. Compile-time persistence can retain adapter function options. |
| `test/jido/instance_test.exs:130-171` | Instance hibernate, thaw, and partitioned persistence work. |
| `test/jido/instance_test.exs:173-225` | The standard children start, generated lifecycle APIs work, partitions isolate equal IDs, and an instance works under another Supervisor. |
| `test/jido/supervisor_test.exs:4-53` | The instance requires a name, has a ten-second child shutdown, and starts the Task, Registry, and Agent supervision services. |
| `test/jido/agent_server/startup_test.exs:96-158` | Dead Registry handles are not live results, invalid Agent startup options return structured errors, and direct `start_link` keeps caller link ownership. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:32-68` | ID, PID, and Registry references cannot cross instance or partition ownership. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:70-97` | Action and Flow work use the selected instance Task Supervisor. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:258-326` | Plugin replacement reads current state. Abnormal Server restart restores the latest nondurable committed state and version. |
| `examples/99_research/99_11_stable_reference/stable_reference.ex:25-47` | An application-level Ref resolves through public lookup on each operation. Core has no Ref. |
| `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:21-80` | Process replacement and separate namespace bindings work in the example. Durable namespace rebinding remains skipped. |
| `guides/core-scope.md:7-22` and `guides/runtime.md:1-27` | Current user guidance supports PID-based Agent Server calls and ID-based instance lifecycle helpers. |
| `guides/configuration.md:1-113` | Current guidance documents instance, Agent, persistence, and observation configuration scopes. |
| `guides/deployment-and-shutdown.md:1-78` | Applications supervise instances and external services. Core local services do not provide cluster ownership or discovery. |

This documentation-only change did not run runtime tests. Skipped research
tests specify a target. They do not prove it.

## Retained baseline

- `INST-RB-001`: An application can define a module with `use Jido` and place
  it in an ordinary supervision tree.
- `INST-RB-002`: A plain atom-named instance supports scripts, Livebook, and
  test isolation. `Jido.Default` is an explicit convenience instance.
- `INST-RB-003`: The current instance tree has five standard local services and
  uses `:one_for_one`.
- `INST-RB-004`: Each instance atom produces separate local service names.
- `INST-RB-005`: Runtime Store data is nondurable. It survives a worker restart
  but not full instance loss.
- `INST-RB-006`: Managed startup returns a PID and links the Server to the
  Dynamic Supervisor, not the request process.
- `INST-RB-007`: ID and partition select local registration. A dead handle is
  not returned as live. Ownership checks protect lifecycle calls.
- `INST-RB-008`: Generated helpers start, stop, find, list, count, hibernate,
  thaw, inspect parent binding, derive service names, and control debug data.
- `INST-RB-009`: Direct Agent Server PID and name APIs are public, documented,
  and tested.
- `INST-RB-010`: A compile-time persistence declaration is the instance
  default. One Agent can override or disable it.
- `INST-RB-011`: A nonpersistent abnormal Server restart restores the latest
  in-instance commit. It does not reset to the initial Agent.
- `INST-RB-012`: Plugin wrappers currently share the Agent Dynamic Supervisor.
- `INST-RB-013`: `config/1` is overridable. No instance child, admission, or
  lifecycle callback exists.
- `INST-RB-014`: External storage clients and application services are not
  implicit instance children.
- `INST-RB-015`: The instance Registry and Runtime Store are local. They do not
  provide transport, discovery, placement, lease, or fencing behavior.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `INST-GAP-001` | `INST-REQ-001` to `INST-REQ-005` | `lib/jido.ex:8-68,236-370`; `lib/jido/application.ex:1-9` | The local application-owned role works. Its exact boundary is spread across docs. | `Retain`; publish one contract |
| `INST-GAP-002` | `INST-REQ-006` to `INST-REQ-009` | `lib/jido.ex:70-142,318-370` | Merge order works. Startup does not validate all instance-owned options as one boundary. | `Retain` order; `Change` validation |
| `INST-GAP-003` | `INST-REQ-010` to `INST-REQ-013` | No namespace or core Ref exists. | Stable identity cannot bind to an instance. | `Change, additive`; blocked on seam 03 |
| `INST-GAP-004` | `INST-REQ-014` to `INST-REQ-018` | `lib/jido.ex:346-420` | The tree and local isolation work. No failure-injection matrix proves the strategy. | `Retain`; strengthen evidence |
| `INST-GAP-005` | `INST-REQ-019` and `INST-REQ-020` | Runtime Store code and tests | Worker-restart retention works. Full-stop cleanup follows ETS ownership but has limited direct proof. | `Retain`; add full-lifetime evidence |
| `INST-GAP-006` | `INST-REQ-021` and `INST-REQ-053` | `lib/jido.ex:357-370`; Agent Server postponement code | `max_tasks` limits Task Supervisor children. Current guidance can be read as a broader runtime limit. | `Retain`; clarify scope |
| `INST-GAP-007` | `INST-REQ-023` to `INST-REQ-026` | Lifecycle code and tests | Current lifecycle and ownership behavior work. Public errors remain mixed. | `Retain`; align errors later |
| `INST-GAP-008` | `INST-REQ-027` to `INST-REQ-030` | Application Ref research example only | No core Ref-first facade, namespace check, or complete-Ref Registry key exists. | `Change, additive` |
| `INST-GAP-009` | `INST-REQ-031` to `INST-REQ-036` | Public Agent Server API and current guides | Direct calls and result meanings work. No Ref delegate exists. Old seam text incorrectly made Agent Server internal. | `Retain` direct API; add facade |
| `INST-GAP-010` | `INST-REQ-037` to `INST-REQ-040` | Generated `config/1`; no other callback | `config/1` is not checked as one final value. Proposed callbacks have no concrete contract or tests. | `Retain` config; `Defer` new callbacks |
| `INST-GAP-011` | `INST-REQ-041` to `INST-REQ-044` | Options and Persistence code | Precedence and delegation work. Invalid defaults can fail only when an Agent consumes them. | `Retain` precedence; validate earlier |
| `INST-GAP-012` | `INST-REQ-045` | Current physical delete in Persistence | No tombstone lifecycle exists. | `Blocked` on seam 07 |
| `INST-GAP-013` | `INST-REQ-046` to `INST-REQ-049` | Instance and Agent Server inspection tests | Current local and debug paths work. Ref-first inspection is absent. | `Retain`; add Ref delegates |
| `INST-GAP-014` | `INST-REQ-050` and `INST-REQ-051` | Structured startup errors plus raw not-found controls | Public result forms are mixed. Ownership rejection works. | `Retain` protocol meaning; migrate through seam 12 |
| `INST-GAP-015` | `INST-REQ-052` | Caller, Directive, readiness, idle, and postponed limits | Limit roles exist across owners. There is no persistence-operation limit. | `Clarify`; defer exact new limit |
| `INST-GAP-016` | `INST-REQ-054` to `INST-REQ-056` | Local Registry and deployment guidance | Core is local, but old facade proposals did not state nonlocal behavior precisely. | `Retain` local boundary |

## Disposition of superseded claims

This table preserves or resolves each distinct claim from the removed seam
files. Git history keeps their exact text.

| Superseded claim or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| The instance module is the application-owned Supervisor and runtime facade. | `Retain`. | This is implemented and matches the library Bright Line. |
| Every instance must have a namespace. | `Replace with additive enablement`. | Plain instances and `Jido.Default` are supported. Ref operations can require namespace without breaking them. |
| Namespace must be globally unique. | `Narrow`. | Require one live binding per exact namespace on one node. Cluster uniqueness and authority are outside this seam. |
| Module name, process name, and namespace are one identity. | `Reject`. | Seam 03 requires stable identity to stay separate from runtime handles. |
| Use `:rest_for_one`, Registry first, and separate Agent and Plugin pools. | `Replace`. | Current code uses five children, `:one_for_one`, and one Dynamic Supervisor. No failure proof supports the proposed redesign. |
| Plugin runtime hosts must never enter the Agent pool. | `Defer placement change`. | Current wrappers share that pool. Seam 08 owns runtime roots. A future split needs coordinated proof. |
| Omit Runtime Store and Spawn Registry from the target tree. | `Reject`. | Both are current instance-owned services with runtime contracts. |
| A nonpersistent Server restart resets to the initial Agent. | `Remove`. | Current code and prerequisite designs keep the latest in-instance committed checkpoint. |
| `Jido.Instance.Config` must replace keyword configuration. | `Remove as the current target`. | No struct exists, and seam 12 requires a proved reason before replacing a supported protocol value. |
| Instance startup must consume one closed observability map. | `Defer`. | Observation has a separate current resolution order and belongs to seam 13. |
| Add `persistence_timeout` as one instance field now. | `Defer`. | Persistence-operation limit meaning is not approved by seams 07, 08, and 12. |
| `start_agent` must change from PID return to Agent Ref return. | `Remove as an in-place change`. | Keep PID compatibility. Add a separate Ref-first publication path. |
| The generated facade must be the only command API. | `Remove`. | Agent Server PID and name functions are public and retained by prerequisite seams. |
| The facade should expose call, cast, request, cancellation, lifecycle, and inspection by Ref. | `Retain as an additive role set`. | Exact names need focused API review. Resolution stays local. |
| Add a public instance `commit` operation. | `Remove`. | Commit occurs inside Agent Server command processing. Seam 06 owns its meaning. |
| Add a separate `plugin_runtimes` operation. | `Remove as required`. | Current `children` inspection can expose bounded runtime status. Seam 08 owns that contract. |
| `whereis_local` must replace `whereis_agent`. | `Defer exact name`. | Current lookup is supported. The new API only needs to identify local PID meaning. |
| Persistent create waits for Plugin readiness and writes revision zero before publication. | `Retain target dependency`. | Seams 07 and 08 own this missing lifecycle. The instance facade must preserve their result. |
| Durable delete is an instance operation over physical adapter delete. | `Replace`. | Expose deletion only after seam 07 provides its approved tombstone contract. |
| All Agents in one instance must use the same persistence provider. | `Remove`. | Current and seam-07 contracts retain explicit per-Agent override or disablement. |
| Add record-valued instance persistence callbacks. | `Remove`. | Seam 07 keeps `Jido.Persistence` above a binary adapter and rejects this layer. |
| `children/1` is the first required callback. | `Defer`. | No current implementation or concrete use case fixes placement, purity, readiness, or failure behavior. |
| Add `configure/1` beside overridable `config/1`. | `Remove for this stage`. | Keep one configuration extension and validate its output. |
| Add instance-wide `admit_agent/2`. | `Defer`. | Agent admission timing, restore access, remote activation, and policy state are unresolved. |
| Add `after_start`, `before_stop`, and Agent lifecycle callbacks. | `Reject`. | Standard supervision, Telemetry, Plugins, and Directives own these needs. |
| Custom instance children start after all standard services. | `Defer`. | There is no approved callback or dependency and rollback contract. |
| External repositories and clients are instance children. | `Reject`. | The application owns and supervises external services. |
| An instance namespace provides remote location and cluster write authority. | `Reject`. | Seams 10 and 11, transport packages, and authority services own those contracts. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the formal plan only after the user approves this seam.

### Phase 0 — Resolve prerequisites and instance decisions

- Requirements: all `INST-REQ` identifiers.
- Required outcome: approved local role, supervision baseline, namespace rule,
  facade roles, persistence precedence, callback scope, and topology limits.
- Constraints: do not treat any pending prerequisite as approved.
- Compatibility: no runtime change.
- Verification: review every `INST-DEC` item and blocker below.
- Exit criteria: the user approves or changes each decision and cross-seam
  conflicts have one owner.

### Phase 1 — Lock the retained local instance contract

- Requirements: `INST-REQ-001` to `INST-REQ-009`, `INST-REQ-014` to
  `INST-REQ-026`, `INST-REQ-031` to `INST-REQ-044`, and `INST-REQ-046` to
  `INST-REQ-056` where current evidence applies.
- Required outcome: public docs and tests describe current OTP composition,
  local services, PID and ID APIs, persistence precedence, inspection, and
  local-only limits without conflicting proposals.
- Constraints: keep Agent Server, Turn, Plugin, commit, and persistence record
  semantics in their owner seams.
- Compatibility: no current API, partition value, result, or callback is
  removed.
- Verification: instance, supervisor, Agent Server lifecycle, persistence,
  guide, and public API characterization checks.
- Exit criteria: each retained requirement has one owner and direct evidence.

### Phase 2 — Validate complete instance configuration

- Requirements: `INST-REQ-006` to `INST-REQ-009`, `INST-REQ-037`,
  `INST-REQ-038`, `INST-REQ-041`, and `INST-REQ-043`.
- Required outcome: one final keyword input is validated before any instance
  child starts, including the instance persistence default.
- Constraints: do not create one cross-package config struct or absorb
  observability and Agent Server option ownership.
- Compatibility: keep application-config and runtime override order and
  overridable `config/1`.
- Verification: invalid type, unknown instance option, persistence callback
  fault, adapter option, application override, and no-child-start tests.
- Exit criteria: every instance-owned invalid input fails before publication.

### Phase 3 — Add stable namespace and local Ref resolution

- Requirements: `INST-REQ-010` to `INST-REQ-013` and `INST-REQ-027` to
  `INST-REQ-030`.
- Required outcome: optional namespace binding, duplicate-local rejection,
  complete-Ref Registry identity, and current-handle resolution on each call.
- Constraints: use the approved seam-03 value. Do not add remote discovery,
  placement, transport, lease, or fencing.
- Compatibility: keep plain instances, `Jido.Default`, term partitions, IDs,
  PIDs, generated names, and current persistence keys until their owner gates.
- Verification: exact namespace validation, duplicate binding, equal IDs in
  two namespaces, wrong namespace, dead and replaced PID, instance restart,
  module rename, and local-only cases.
- Exit criteria: one Ref remains stable while each local handle can change.

### Phase 4 — Add the Ref-first facade and durable lifecycle integration

- Requirements: `INST-REQ-027` to `INST-REQ-036`, `INST-REQ-044`,
  `INST-REQ-045`, `INST-REQ-048`, `INST-REQ-050`, and `INST-REQ-052`.
- Required outcome: one reviewed Ref-first family delegates to public Agent
  Server and persistence operations with one lookup and error policy.
- Constraints: no private messages, commit API, route selection, result
  rewriting, or implicit remote forward.
- Compatibility: additive API only. Durable create, tombstone, and error
  rollout follow seams 07, 08, and 12 as one compatible unit.
- Verification: function inventory, success and every lookup failure, commit
  meaning, cast and request protocols, lifecycle, inspection, timeout ownership,
  and public-only external fixture.
- Exit criteria: every Ref role works without private Server access and all
  current paths still pass.

### Phase 5 — Prove restart boundaries and close release evidence

- Requirements: all approved `INST-REQ` identifiers.
- Required outcome: failure coupling, nondurable lifetime, durable delegation,
  and dependent-seam use match the approved contract.
- Compatibility: any future supervision or Plugin-pool change is a separate
  migration with rollback proof.
- Verification: kill each standard child, stop and restart the complete
  instance, exercise equal identities in two instances, run focused and full
  Jido checks, and run the compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing`, `Conflict`, or
  `Blocked` state for an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `INST-REQ-001` to `INST-REQ-005` | Instance and package Application code and tests | Public role inventory and no-global-instance test | `Proven` |
| `INST-REQ-006` and `INST-REQ-007` | Generated instance and config merge tests | Keep exact precedence in one contract test | `Proven` |
| `INST-REQ-008` and `INST-REQ-009` | Child and Agent options validate at separate points | Final instance input and no-child-start matrix | `Partial` |
| `INST-REQ-010` to `INST-REQ-013` | Application Ref example only | Core namespace binding, Ref creation, duplicate, and separation tests | `Missing` |
| `INST-REQ-014` to `INST-REQ-018` | Instance and supervisor tests | Kill and generation checks for all five services | `Partial` |
| `INST-REQ-019` and `INST-REQ-020` | Runtime Store worker-restart test and ETS ownership | Complete instance stop and new-generation empty-store test | `Partial` |
| `INST-REQ-021` and `INST-REQ-022` | Task child limit and application guidance | Exact max-child and external-service ownership tests | `Partial` |
| `INST-REQ-023` to `INST-REQ-026` | Instance and runtime lifecycle tests | Stable public inventory and seam-12 result mapping | `Proven` for current protocols; target errors are `Partial` |
| `INST-REQ-027` to `INST-REQ-030` | Application Ref example | Complete additive facade and resolution matrix | `Missing` |
| `INST-REQ-031` to `INST-REQ-034` | Public Agent Server code and tests | Ref delegate parity for call, cast, and request | `Proven` for direct API; facade is `Missing` |
| `INST-REQ-035` and `INST-REQ-036` | Current facade delegates lifecycle only | Signal immutability and dispatch-result parity tests through Ref facade | `Partial` |
| `INST-REQ-037` and `INST-REQ-038` | `config/1` is overridable | Invalid override result and pre-child failure tests | `Partial` |
| `INST-REQ-039` and `INST-REQ-040` | No callback code exists; OTP and Telemetry alternatives exist | Public callback inventory and application composition fixture | `Proven` for absence; target documentation is `Partial` |
| `INST-REQ-041` to `INST-REQ-043` | Persistence resolution and adapter tests | Instance-start validation plus override and disablement parity | `Partial` |
| `INST-REQ-044` | Current hibernate, thaw, restore, and write tests | Initial-record, all-write-result, and Ref integration matrix | `Partial` |
| `INST-REQ-045` | Physical delete only | Approved tombstone facade and conflict tests | `Blocked` |
| `INST-REQ-046` and `INST-REQ-047` | Instance listing and dead-entry tests | Keep with complete-Ref Registry keys | `Proven` |
| `INST-REQ-048` | Direct Server inspection exists | Ref-first inspection parity and wrong-instance tests | `Missing` |
| `INST-REQ-049` | Generated debug and recent-event functions | Keep exact bounded behavior through facade changes | `Proven` |
| `INST-REQ-050` and `INST-REQ-051` | Structured startup errors and ownership tests | Full seam-12 operation matrix | `Partial` |
| `INST-REQ-052` and `INST-REQ-053` | Current independent limit fields | Owner, start, end, timeout, and uncertainty matrix | `Partial` |
| `INST-REQ-054` to `INST-REQ-056` | Local code and deployment guidance | Nonlocal Ref rejection and architecture checks | `Partial` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Instance startup | Keep module instances, plain atom instances, `Jido.Default`, and standard OTP child specs. |
| Configuration | Keep keyword input, application-config then runtime precedence, and overridable `config/1`. Add validation before children. |
| Local names | Keep atom-derived service names. Namespace must not rename running OTP services. |
| Namespace | Add it as optional. Ref operations fail clearly when it is absent. Do not require it for current ID and PID calls. |
| Partition | Keep current term-valued options. Convert to the seam-03 binary Ref field only through an explicit collision-checked rule. |
| Registry | Keep current ID and partition lookup while adding complete-Ref keys or a compatible index. A mixed release must prevent duplicate live identity. |
| PID and Server API | Keep current return values and public Agent Server functions. Add Ref-first calls before any later deprecation review. |
| `start_agent` | Keep PID return. Use a separate reviewed Ref-first publication entry instead of changing the return in place. |
| Persistence | Keep instance default plus per-Agent override or disablement. Keep legacy keys readable until seam-07 migration and rollback gates pass. |
| Durable lifecycle | Release initial create, tombstones, write-authority errors, and activation behavior as one compatible change. |
| Runtime checkpoints | Keep last-commit recovery for abnormal Server restart and cleanup on complete instance stop. |
| Supervision | Keep the current tree first. Any strategy, order, or pool change needs failure tests and a rollback rule. |
| Callbacks | Keep `config/1`. Add no child, admission, or lifecycle callback in this stage. |
| Status and debug | Keep current maps, phases, debug controls, and bounded event access. Seam 13 owns later projection changes. |
| Errors | Preserve documented `nil`, `:ok`, OTP request, and lifecycle controls while seam 12 converts other failures one boundary at a time. |
| Topology | Keep local-only resolution. Add no implicit transport or Controller fallback. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `INST-BLK-001` | `Blocker` | 00 Overview | Local runtime, stable Ref, compatibility, and topology limits are pending approval. | Approve them or replace them with explicit instance assumptions. |
| `INST-BLK-002` | `Blocker` | 90 Package boundaries | Core, cluster, durable, transport, and extension ownership are pending approval. | Approve or change the package boundary. |
| `INST-BLK-003` | `Blocker` | 12 Errors and contracts | Instance error codes and the protocol-value registry are pending. | Approve them before Ref facade result types close. |
| `INST-BLK-004` | `Blocker` | 03 Agent identity | Core Ref, binary partition conversion, equality, and portable encoding do not exist. | Approve the Ref and migration rules. |
| `INST-BLK-005` | `Blocker` | 07 Persistence | Ref keys, legacy reads, collision checks, tombstones, and persistence-operation limits are not approved. | Approve record migration and lifecycle before durable Ref operations. |
| `INST-BLK-006` | `Blocker` | 08 Agent Server | Initial durable create, all-write-error authority loss, and final public error meanings are not implemented. | Align Server readiness and failure behavior with seam 07. |
| `INST-BLK-007` | `Assumption` | 09 Jido instance | One live exact namespace binding per node is sufficient for the local facade. | Approve or change `INST-DEC-003`. |
| `INST-BLK-008` | `Blocker` | 09 Jido instance | Exact Ref-first function names, arities, tagged results, and bang variants are open. | Complete a focused API naming review after identity approval. |
| `INST-BLK-009` | `Assumption` | 09 Jido instance, 07 Persistence | Per-Agent persistence override and disablement remain supported. | Approve or change `INST-DEC-005`. |
| `INST-BLK-010` | `Assumption` | 09 Jido instance | The current five-child `:one_for_one` tree is the first-stage target. | Approve it or provide failure evidence for another tree. |
| `INST-BLK-011` | `Assumption` | 05 Plugins, 08 Agent Server | Plugin wrappers can remain in the current Dynamic Supervisor during first-stage alignment. | Change placement only through the owning runtime contract. |
| `INST-BLK-012` | `Assumption` | 10 Runtime topology, 11 Control plane | Ref-first instance operations are local and do not use Topology or transport fallback. | Keep nonlocal routing in an explicit owner API. |
| `INST-BLK-013` | `Resolved` | Design index | The main review table now lists the Jido instance briefing, design, and alignment files. | Keep repository-wide link checks in the documentation gate. |

## Completion criteria

- [ ] The user has approved or changed every `INST-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `INST-REQ` item has `Proven` evidence.
- [ ] No unresolved `Missing`, `Conflict`, or `Blocked` state remains for an
      approved requirement.
- [ ] Complete instance configuration fails before child startup when invalid.
- [ ] Namespace and Ref tests cover duplicate binding, instance restart, module
      rename, wrong instance, replacement PID, and local-only behavior.
- [ ] Ref-first roles work through public Agent Server functions only.
- [ ] Current ID, PID, partition, persistence, debug, and direct Server APIs
      remain supported until their separate migration gates pass.
- [ ] Each standard child has failure-coupling and full-instance cleanup proof.
- [ ] Durable lifecycle behavior matches approved seams 07 and 08.
- [ ] No instance requirement defines Signal routing, persistence records,
      placement, transport, cluster authority, or topology control.
- [ ] After approval, a separate formal implementation plan defines tasks.
