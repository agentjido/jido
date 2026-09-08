# Overview seam alignment plan

> Planning document. This document is pending approval. Code in `lib`, public
> module documentation, and executable tests define current behavior.

## 1. Purpose, scope, and owner

This document gives the shared architecture plan for Jido V3. It defines the
model, vocabulary, ownership boundaries, and cross-system invariants that later
seams use. Approval of this document sets planning gates. It does not change a
runtime contract by itself.

The `00_overview` seam owns:

- the shared Agent, Turn, commit, effect, durability, and runtime model;
- the names and meanings of cross-system concepts;
- the boundary between Jido, OTP, `jido_action`, and `jido_signal`;
- the categories of extension points;
- cross-system invariants and their detailed seam owners;
- the order in which later seams can finalize their contracts.

This seam does not own detailed structs, callback signatures, error codes,
storage operations, supervision strategies, or topology update protocols.
Those contracts stay with their numbered seams.

There is no prerequisite alignment document. This is the first planning gate
in the dependency graph in `docs/design/AGENTS.md`.

## 2. Inputs reviewed

### Design and public documentation

The review used these design rules and baseline documents:

- `docs/design/AGENTS.md`
- `docs/design/README.md`
- `docs/design/99_delivery/planning-baseline.md`
- `guides/core-scope.md`
- `guides/extension-boundaries.md`

The review used every document in this seam:

- `docs/design/00_overview/README.md`
- `docs/design/00_overview/architecture.md`
- `docs/design/00_overview/invariants.md`
- `docs/design/00_overview/glossary.md`
- `docs/design/00_overview/gap-analysis.md`

The review also checked these later-seam proposals where they affect an
overview decision:

- `docs/design/03_agent-identity/README.md`
- `docs/design/03_agent-identity/gap-analysis.md`
- `docs/design/04_turn-evaluation/gap-analysis.md`
- `docs/design/05_plugins/plugin-facets.md`
- `docs/design/08_agent-server/agent-server.md`
- `docs/design/08_agent-server/gap-analysis.md`
- `docs/design/09_jido-instance/gap-analysis.md`
- `docs/design/10_runtime-topology/gap-analysis.md`
- `docs/design/10_runtime-topology/remote-owned-children.md`
- `docs/design/11_topology-control-plane/topology-authoring-host.md`
- `docs/design/12_errors-and-contracts/gap-analysis.md`
- `docs/design/13_observability/gap-analysis.md`
- `docs/design/90_package-boundaries/runtime-extension-boundaries.md`
- `docs/design/90_package-boundaries/gap-analysis.md`

### Canonical code and public module documentation

The review used these primary modules:

- `lib/jido.ex`
- `lib/jido/agent.ex`
- `lib/jido/agent/builder.ex`
- `lib/jido/agent/codec.ex`
- `lib/jido/agent/command.ex`
- `lib/jido/agent/command/runner.ex`
- `lib/jido/agent/turn.ex`
- `lib/jido/agent/turn/outcome.ex`
- `lib/jido/agent_server.ex`
- `lib/jido/agent_server/state.ex`
- `lib/jido/agent_server/runtime_checkpoint.ex`
- `lib/jido/agent_server/plugin_lifecycle.ex`
- `lib/jido/plugin.ex`
- `lib/jido/plugin/spec.ex`
- `lib/jido/plugin/init.ex`
- `lib/jido/persistence.ex`
- `lib/jido/persistence/adapter.ex`
- `lib/jido/topology.ex`
- `lib/jido/topology/plan.ex`
- `lib/jido/topology/controller.ex`
- `lib/jido/topology/controller/activation.ex`
- `lib/jido/error.ex`
- `lib/jido/telemetry.ex`
- `lib/jido/telemetry/agent.ex`
- `lib/jido/observe.ex`
- `lib/jido/observe/tracer.ex`
- `lib/jido/debug.ex`
- `mix.exs`

The review also checked the direct lower-layer boundaries:

- `../jido_action/lib/jido_exec.ex`
- `../jido_signal/lib/jido_signal/router.ex`
- `../jido_signal/lib/jido_signal/router/index.ex`

### Executable test evidence

The review used these representative tests:

- `test/jido/agent_test.exs`
- `test/jido/agent/builder_test.exs`
- `test/jido/agent/codec_test.exs`
- `test/jido/plugin/contract_test.exs`
- `test/jido/agent_server/public_api_test.exs`
- `test/jido/agent_server/directive_execution_test.exs`
- `test/jido/agent_server/runtime_boundary_test.exs`
- `test/jido/agent_server/runtime_lifecycle_test.exs`
- `test/jido/persistence_test.exs`
- `test/jido/persistence/indeterminate_write_test.exs`
- `test/jido/persistence/checkpoint_portability_test.exs`
- `test/jido/instance_test.exs`
- `test/jido/supervisor_test.exs`
- `test/jido/topology/controller_test.exs`
- `test/jido/topology/composition_test.exs`
- `test/jido/topology/authoring_host_test.exs`
- `test/jido/error_test.exs`
- `test/jido/error/normalization_test.exs`
- `test/jido/error_transport_test.exs`
- `test/jido/telemetry/agent_test.exs`
- `test/jido/observe/agent_lifecycle_test.exs`
- `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs`
- `test/examples/99_research/99_09_route_selection/route_selection_test.exs`
- `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs`
- `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs`
- `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs`
- `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs`

The review did not run tests. This task changes planning documents only. The
verified test results in `docs/design/99_delivery/planning-baseline.md` and
`docs/design/00_overview/gap-analysis.md` remain the current execution record.

## 3. Current architecture baseline

This section states implemented behavior only.

### 3.1 Values and direct evaluation

- `%Jido.Agent{}` is the immutable Agent value. It represents a neutral
  definition or an instance with an ID and complete state.
- Spark DSL, direct declarations, inline Actions, Builder, and Codec all use
  the Agent validation boundary.
- `Jido.Agent.cmd/3` evaluates one Signal and returns a candidate Agent and a
  Directive list. It does not make the candidate live and does not dispatch the
  Directives.
- `%Jido.Agent.Command{}` and `%Jido.Agent.Turn{}` are the current command and
  executable-selection values. `%Jido.Agent.Turn.Outcome{}` is the current
  public terminal live-Turn value.
- `Jido.Agent.Command.Runner` is private. It is the shared direct and live
  evaluation mechanism.

### 3.2 Current Turn path

The current direct path is:

```text
source Signal
  -> sequential Plugin prepare chain
  -> route the prepared Signal
  -> require exactly one matching target
  -> run one Action or Flow through Jido.Exec
  -> protect Plugin-owned state
  -> validate Directives
  -> reduce Plugin-owned state in declaration order
  -> validate and return one candidate Agent and Directive list
```

The live path adds asynchronous admission before this direct path. Admission
can also change the Signal. The Agent Server then persists the next state when
configured, installs the candidate, increments `state_version`, replies to the
caller, and handles Directives in order.

The Signal Router returns all matches in precedence order. Jido currently
rejects zero or multiple targets. It does not select the first target.

### 3.3 State, commit, effects, and recovery

- The Action or Flow returns the complete proposed state. It cannot change a
  Plugin-owned state key. Each stateful Plugin owns at most one state key and
  can replace only that complete value.
- One successful live Turn has one commit point and increments
  `state_version` once. A pre-commit error preserves state and version. A
  post-commit Directive error preserves both.
- Actions and Flows can perform synchronous I/O before commit. That I/O is not
  rolled back when evaluation fails.
- Directive work starts after commit. Ordinary Directive dispatch has no
  general crash-recovery promise.
- Saved Plugin state can contain durable work intent. Built-in Scheduler tests
  show stable occurrence IDs, retry, and acknowledgement through a later
  Signal and commit.

### 3.4 Process and instance boundaries

- One Agent Server is the serialized OTP owner of one live Agent.
- A Jido instance starts one Task Supervisor, one Registry, one Runtime Store,
  one Spawn Registry, and one Dynamic Supervisor for Agent Servers and Plugin
  runtime wrappers. The instance supervisor uses `:one_for_one`.
- Plugin runtime handles stay in private Agent Server state. They do not enter
  the Agent or its checkpoint.
- Public Agent Server operations accept a PID, registered name, global name,
  or `:via` value. Jido instance helpers start, find, stop, hibernate, and thaw
  Agents. Startup and lookup return PIDs.
- A nonpersistent named-instance Server saves each successful commit to the
  instance Runtime Store. An abnormal Server restart restores the latest saved
  Agent and state version. A full instance stop removes this nondurable state.
- A persistent Server loads the latest durable record. Plugin runtimes start
  and become ready before startup returns. Startup does not write an initial
  durable record.

### 3.5 Durability boundary

- `Jido.Persistence` owns Agent keys, private record maps, record validation,
  checkpoint encoding, and adapter fault containment.
- `Jido.Persistence.Adapter` owns binary `get`, `put`, atomic
  `compare_and_swap`, and `delete` operations. It does not own Agent lifecycle
  policy.
- A live commit uses the current Agent `state_version` as the expected
  revision. An uncertain write stops the Server. A confirmed conflict or
  adapter error can pass to the configured error policy and can leave the
  Server running.
- Delete removes the adapter record. It does not keep a tombstone or revision
  history.
- The current checkpoint and record are plain maps. They contain no stable
  definition revision or canonical Agent Ref.

### 3.6 Topology, errors, and observation

- Topology definitions and plans are immutable values. DSL, Builder, and Codec
  use the same validation and planning path.
- The static local Topology Controller activates the existing plan, reports
  readiness, and performs automatic or manual repair. It has no live target
  update, owner-Agent runtime, cluster placement, or ownership transfer.
- `Jido.Error` defines six Splode error structs. Some public protocol results
  still use atoms, tuples, and maps.
- Semantic Agent telemetry separates lifecycle, Turn, commit, Directive, and
  terminal settlement events. Bounded metadata excludes state, payloads,
  process handles, caller context, and raw error data.
- Older `:agent_server` telemetry, the `Jido.Observe` tracer path, and local
  debug buffers remain public or supported compatibility paths.

### 3.7 Current package direction

- `jido_action` owns Actions, Instructions, Flows, and `Jido.Exec`.
- `jido_signal` owns the Signal envelope, ordered route matching, dispatch, and
  local Signal bus.
- `jido` uses those lower layers. It owns Agents, Plugins, Agent Server,
  instances, local topology, core persistence, errors, and observation.
- The current `jido` checkout uses a sibling path for `jido_action` and a Hex
  V3 requirement for `jido_signal`. Cross-package tests must use compatible V3
  versions.

## 4. Target shared architecture for V3

This section is the recommended overview target. Approval confirms the shared
model. Later seams still own their detailed contracts.

### 4.1 Major values and owners

| Value or concept | Overview owner and rule | Detailed owner |
| --- | --- | --- |
| Signal | The immutable input envelope. Keep the received value as the source Signal. | `jido_signal` owns the value. Seams 04 and 05 own Jido use. |
| Agent definition | Static schema, routes, Plugin declarations, metadata, and an optional or required definition revision. It has no live runtime state. | 01 and 02 |
| Agent instance | Immutable domain and Plugin-owned portable state for one Agent ID. It has no live process handles. | 01 |
| Agent Ref | The proposed stable identity for lookup, storage, and delivery. It must be separate from a PID and runtime location. | 03, then 09 and 07 |
| Turn | One fixed executable selection and its input for one source Signal. | 04 |
| Candidate Agent | The complete validated Agent returned by direct evaluation and offered to the live owner for commit. | 01 and 04 |
| State version | The live commit revision. One successful Turn increments it once. | 06 and 08 |
| Live result | The current tagged success or error reply at the commit boundary. It is not a new `Result` struct. | 08 and 12 |
| Turn Outcome | The terminal observation after post-commit Directive work settles. It does not replace the live result. | 08 and 13 |
| Directive | A typed request for runtime-owned work after commit. | 06, 08, and the owning Plugin |
| Checkpoint | Portable Agent reconstruction data. It contains no runtime handles. | 01 and 07 |
| Persistence record | The durable lifecycle and compare-and-swap envelope around saved Agent state. Its exact public shape is not set here. | 07 |
| Topology definition and plan | Static desired composition and one expanded local plan. | 11 |

Do not add the proposed public structs from `architecture.md` only because they
appear in that document. Each owning seam must first define purpose,
compatibility, serialization, and error behavior.

### 4.2 Recommended data flow

Subject to approval item A-01, use this shared order:

```text
source Signal
  -> live admission, which can accept, reject, or add bounded context
  -> select the first route target from the source Signal by Router precedence
  -> fix the executable for the Turn
  -> prepare isolated Plugin-owned input in declaration order
  -> run one Action or Flow through Jido.Exec
  -> assemble Plugin contributions in declaration order
  -> validate one candidate Agent and Directive batch
  -> persist when durability is configured
  -> install the candidate and increment the state version once
  -> return the live result
  -> handle Directives in order
  -> publish one terminal Turn Outcome
```

Admission must not change executable selection. A later seam must define which
Signal fields admission can change and how those changes become the effective
Signal. The route predicate sees the source Signal. The executable and Plugins
can receive an effective Signal or prepared input as defined by seams 04 and
05. Those details are not final here.

### 4.3 State and effect boundaries

- Agent domain state and Plugin-owned state are separate ownership classes.
  Seams 01 and 05 decide their physical field layout and migration.
- The selected Action or Flow is the only writer of domain state during a
  Turn. A Plugin can write only its declared complete state slice.
- Jido alone assembles and validates the candidate Agent.
- Actions and Flows can do synchronous I/O before commit. Applications own
  idempotency and recovery for that work.
- Directive handling is runtime-owned post-commit work. It has a separate
  failure and observation boundary.
- A capability that promises recovery must store portable work intent and a
  stable operation ID in Agent or Plugin state. Core does not make every
  Directive durable.

### 4.4 Process boundaries

- An Agent Server is the only serialized live owner of one Agent activation.
- A PID is a runtime handle. It is not durable identity.
- The Jido instance owns local lookup, supervision, task execution, local
  runtime checkpoints, and persistence selection for its live Agents.
- Plugin runtime processes are capability resources, not Agent peers. Their
  exact pool placement and restart coupling belong to seams 09 and 10.
- OTP owns mailboxes, process scheduling, monitoring, supervision, timers,
  exits, and shutdown. Jido owns domain meaning, commit policy, and recovery
  rules built on those OTP services.
- Current PID APIs stay supported during any Ref-first migration. No overview
  approval removes them.

### 4.5 Durability boundary

- A durable live commit becomes visible only after a confirmed successful
  compare-and-swap write.
- No Directive starts when the durable write is not confirmed.
- The recommended target removes write authority after every persistence write
  error. Seams 07 and 08 must define confirmed conflict, confirmed failure,
  uncertain result, reload, and restart behavior.
- The recommended persistent-create target is: start provisional Plugin
  runtimes, wait for readiness, write the initial active record at state
  version zero, and only then report the Agent as ready. Seams 07, 08, and 10
  own failure cleanup and publication details.
- The recommended normal-delete target writes a compare-and-swap tombstone.
  Seam 07 owns retention, purge, reactivation, and next-writer rules.
- The existing binary adapter remains the storage I/O boundary. A Plugin or
  persistence facet cannot change a compare-and-swap result.

### 4.6 Extension categories

Use one term and one owner for each extension type:

| Extension category | Purpose | Boundary rule |
| --- | --- | --- |
| Plugin package | A reusable Agent capability declared by the user. | Keep the ordered declaration experience during migration. |
| Plugin facet | A proposed owner-specific Plugin behavior for Agent, Agent Server, Persistence, or Topology. | The four-facet model needs approval. Exact callbacks belong to seam 05. |
| Adapter | A replaceable external service boundary, such as persistence or Signal dispatch. | It does not own Agent lifecycle or Plugin state policy. |
| Authoring extension | Static DSL syntax that lowers to canonical Agent or Topology values. | It does not run Turn, persistence, or lifecycle work. |
| Directive handler | Runtime work for one typed Directive after commit. | It cannot change the committed result. |
| Tracer or telemetry handler | Observation and export. | It cannot change results or runtime outcomes. |

Do not turn `Jido.Plugin` into a universal extension behavior. `Jido.Exec`,
Signal dispatch adapters, persistence adapters, authoring extensions, and
tracers keep separate contracts.

### 4.7 Topology and package direction

- Keep the current static Topology definition, plan, local Controller,
  readiness, and repair as the implemented baseline.
- Treat the combined Topology authoring host and its owner Agent value as
  implemented authoring. Do not claim that the owner Agent controls the live
  topology until seam 11 defines and proves that runtime.
- Live target updates, rolling changes, and resumable topology upgrades remain
  open in seam 11 and delivery planning.
- Keep Jido core as a complete local Agent runtime. Put general recovery scans,
  leases, fencing, and storage maintenance in a durable package. Put membership,
  placement, rebalance, and failover in a cluster package. Put gateways,
  authentication, and durable inboxes in a transport package.
- Add a core extension API only when an integration otherwise needs private
  Server state, private messages, or generated runtime names.

## 5. Invariant reconciliation

The classification means:

- **Retained:** current behavior and the recommended target agree.
- **Changed:** the recommended wording or behavior differs from current code
  or from the current overview text.
- **Deferred:** the rule can be a later target, but its detailed owner must
  decide it before it becomes a V3 requirement.
- **Rejected:** remove the proposed rule and retain the evidenced current rule.

### 5.1 Turn and Plugin boundaries

| ID | Class | Code evidence | Recommended wording | Migration effect | Detailed owner |
| --- | --- | --- | --- | --- | --- |
| INV-T01 | Retained | `lib/jido/agent/command/runner.ex`; `test/jido/agent_server/public_api_test.exs` | The Agent path works with no Plugins. | None. | 01 and 04 |
| INV-T02 | Changed | Router order: `../jido_signal/lib/jido_signal/router/index.ex`; exact-one policy: `lib/jido/agent/command/runner.ex`; skipped proof: `test/examples/99_research/99_09_route_selection/route_selection_test.exs` | Jido selects the first matching route target in Signal Router precedence order. | Ambiguous routes change from an error to a deterministic selection. Add a staged compatibility note. | 04, with 01 |
| INV-T03 | Changed | `lib/jido/agent.ex` and `lib/jido/agent/command/runner.ex` prepare before routing today. | Route selection uses the source Signal and completes before pure Plugin preparation. | A Plugin that changes Signal type can no longer redirect the Turn. | 04 and 05 |
| INV-T04 | Changed | `lib/jido/plugin.ex`; route test above | After selection, Plugin work cannot replace the executable or cause another route lookup. | Add validation and migration evidence for current route-changing Plugins. | 04 and 05 |
| INV-T05 | Retained | `lib/jido/agent/command/runner.ex`; `lib/jido/agent_server.ex` | Direct `Agent.cmd/3` and live Server execution use the same candidate-evaluation boundary. | Preserve direct and live parity tests. | 04 and 08 |
| INV-T06 | Retained | `lib/jido/plugin.ex`; `test/jido/plugin/contract_test.exs` | During a Turn, the Action or Flow is the only writer of domain state. | Preserve behavior. | 01, 04, and 05 |
| INV-T07 | Retained | `lib/jido/agent/command/runner.ex`; `lib/jido/plugin.ex` | Plugin state reducers do not receive or change the complete executable output. | Preserve the narrow reducer input. | 05 |
| INV-T08 | Retained | `lib/jido/plugin/spec.ex`; `test/jido/plugin/contract_test.exs` | Each stateful Plugin owns at most one complete Plugin state entry. | Preserve during facet migration. | 05 |
| INV-T09 | Retained | `lib/jido/plugin.ex`; `test/jido/plugin/contract_test.exs` | A Plugin can replace only its complete owned state entry. | Preserve strict ownership checks. | 01 and 05 |
| INV-T10 | Changed | `%Jido.Agent.Command{}` contains the full Agent; isolation tests are skipped in `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs`. | Each Plugin receives only its declared Agent view, its owned prepared input, and the Directives that it owns. | Add observed-field declarations and isolated prepared inputs. Exact values and merge rules stay open. | 05, with 01 and 04 |
| INV-T11 | Retained | `lib/jido/plugin.ex`; `test/jido/plugin/contract_test.exs` | Plugin preparation and state contribution run serially in declaration order. | Preserve order while changing input ownership. | 05 |
| INV-T12 | Retained | `lib/jido/agent/command/runner.ex` | Only Jido assembles and validates the candidate Agent. | Preserve behavior. | 01 and 04 |

### 5.2 Commit, persistence, and recovery

| ID | Class | Code evidence | Recommended wording | Migration effect | Detailed owner |
| --- | --- | --- | --- | --- | --- |
| INV-C01 | Retained | `lib/jido/agent_server.ex`; `test/jido/agent_server/public_api_test.exs` | Live Agent state has one commit point. | None. | 06 and 08 |
| INV-C02 | Retained | `lib/jido/agent_server.ex`; `lib/jido/agent/turn/outcome.ex` | Each successful Agent state commit increments the state version by one, including an equal-state result. | Preserve tests for success and pre-commit failure. | 06 and 08 |
| INV-C03 | Changed | `lib/jido/agent.ex`; `lib/jido/agent_server.ex` | Runtime-owned Directive work starts after commit. An Action or Flow can perform synchronous I/O before commit. | Correct the broad effect claim. No runtime change is required. | 06 |
| INV-C04 | Retained | `lib/jido/plugin/scheduler.ex`; `test/jido/plugin/scheduler/occurrence_recovery_test.exs` | A capability that promises durable work stores portable intent and stable IDs with the business change in one checkpoint. | Keep this capability-specific. Do not create a universal outbox. | 05, 06, and 07 |
| INV-C05 | Retained | Scheduler runtime and recovery tests | A supervised capability worker resumes its saved pending work after startup. | Preserve the proven pattern. | 05 and 10 |
| INV-C06 | Retained | Scheduler acknowledgement path and tests | Durable-work completion enters through a new Signal and normal Agent commit. | Preserve the normal Turn boundary. | 05 and 06 |
| INV-C07 | Retained | Scheduler state and `guides/core-scope.md` | Later Turns preserve pending work. Core has no universal durable outbox gate. | None. | 05 and 06 |
| INV-C08 | Retained | `lib/jido/agent_server.ex`; Directive failure tests | Ordinary Directive handling does not promise crash recovery. | Document this on each Directive API. | 06 and 08 |
| INV-C09 | Retained | `lib/jido/persistence.ex`; `lib/jido/persistence/adapter.ex` | Persistence updates use atomic compare-and-swap. | Preserve the binary adapter contract. | 07 |
| INV-C10 | Changed | `lib/jido/agent_server.ex`; `test/jido/persistence_test.exs` | Only a confirmed successful persistence write lets the activation keep write authority. | Confirmed conflicts and confirmed write errors must no longer continue as writable activations. | 07 and 08 |
| INV-C11 | Changed | Only uncertain writes always stop in `lib/jido/agent_server.ex`. | Every persistence write error removes write authority. The Server must stop or enter a non-writing terminal state defined by its owner. | This changes configurable error-policy behavior. Add a compatibility note and restart proof. | 07 and 08 |
| INV-C12 | Changed | `Jido.Persistence.delete_agent/4` calls adapter delete; the tombstone test is skipped. | Normal durable deletion writes a compare-and-swap tombstone. | Replace blind deletion only after retention, purge, and reactivation rules exist. | 07 |

### 5.3 Definition, identity, and lifecycle

| ID | Class | Code evidence | Recommended wording | Migration effect | Detailed owner |
| --- | --- | --- | --- | --- | --- |
| INV-D01 | Changed | `%Jido.Agent{}` has no definition revision; `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs` is partly skipped. | Module-authored Agent definitions have a positive module-owned definition revision. Other authoring forms must preserve the same normalized field. | Add a compatible default and Codec migration. Do not remove Builder or Codec. | 01 and 02 |
| INV-D02 | Changed | `Jido.Agent.restore/3` can use the current module definition without a saved revision check. | Restore checks the saved Agent module and definition revision before state becomes live. | Old checkpoints need a stated legacy rule. Complete code pinning remains a separate problem. | 01, 04, and 07 |
| INV-D03 | Changed | Registry and persistence use different identity shapes; no core Ref exists. | Registry, persistence, Agent delivery, and placement use one stable Agent Ref after a staged migration. | Add a Ref-first facade while current ID and PID APIs remain supported. | 03, then 07, 09, and 10 |
| INV-D04 | Retained | Agent values exclude PIDs; public lookup returns a replaceable PID. | A PID is a runtime handle, not durable Agent identity. | Keep PID APIs as compatibility handles. | 03 and 09 |
| INV-D05 | Retained | `lib/jido/agent_server.ex`; `test/jido/persistence_test.exs` | Persistent Server restart loads the latest valid durable record. | Preserve behavior while record shape changes. | 07 and 08 |
| INV-D06 | Rejected | `lib/jido/agent_server/runtime_checkpoint.ex`; `test/jido/agent_server/runtime_lifecycle_test.exs` | A nonpersistent Server in a named Jido instance restores its latest in-instance runtime checkpoint after an abnormal Server restart. A full instance stop removes that checkpoint. | Remove the reset-to-initial proposal. Keep the implemented restart guarantee. | 08, 09, and 10 |
| INV-D07 | Changed | Live persistence uses instance context, but per-Agent overrides and direct Persistence calls exist. | Live Server persistence runs through the owning Jido instance context. Direct Persistence APIs remain explicit protocol entry points during migration. | Seam 09 and seam 90 must decide whether per-Agent adapter selection stays. | 07, 09, and 90 |
| INV-D08 | Changed | Plugin readiness exists, but initial durable write does not. | Persistent creation makes provisional Plugin runtimes ready, writes the initial active record at state version zero, and then reports readiness. | Add cleanup and retry rules before implementation. | 07, 08, and 10 |

### 5.4 Runtime boundaries

| ID | Class | Code evidence | Recommended wording | Migration effect | Detailed owner |
| --- | --- | --- | --- | --- | --- |
| INV-R01 | Retained | `lib/jido.ex`; `test/jido/supervisor_test.exs` | Every Agent Server is a peer in the Jido Agent activation pool. | Preserve this logical peer model. | 09 and 10 |
| INV-R02 | Changed | Plugin wrappers currently use the same Dynamic Supervisor in `lib/jido/agent_server/plugin_lifecycle.ex`. | Plugin runtime hosts are capability resources, not Agent peers. Physical pool separation is a later runtime-topology decision. | Do not claim current physical separation. A later pool split needs restart-cascade tests. | 09 and 10 |
| INV-R03 | Changed | `%Jido.Plugin.Init{}` lacks committed Plugin state and state version; the FA-06 proof is skipped. | Every Plugin runtime replacement starts from one current committed Plugin state value and the matching Agent state version. | Add a fresh Init path. Keep the public state-pull path during migration. | 05, 08, and 10 |
| INV-R04 | Retained | Agent checkpoints are portable; runtime handles stay in private Server state. | Runtime handles and executable workflow state never enter Agent state or checkpoints. | Preserve and broaden portability tests. | 01, 05, 07, and 10 |
| INV-R05 | Retained | Agent Server cancel paths act before commit. | Only admission and executable evaluation before commit are cancellable. | Keep caller timeout separate from cancellation. | 04 and 08 |
| INV-R06 | Retained | Commit and Directive paths have no active-turn cancellation operation. | Commit and Directive handling are not cancellable through the Turn cancel API. | Preserve behavior and document it. | 06 and 08 |
| INV-R07 | Deferred | Caller timeout does not cancel work. `Jido.Exec` has execution timeout, but the Server has no independent `turn_timeout`. | A live Turn execution limit, if added, is distinct from caller wait timeout and Directive timeout. | No release promise until seams 04 and 08 define start, stop, and Outcome rules. | 04 and 08 |
| INV-R08 | Retained | Plugin runtimes use public Agent Server calls and Signals to change Agent state. | Plugin runtimes request state changes through Signals and the Agent mailbox. | Preserve this boundary. | 05 and 08 |

### 5.5 Public values, errors, and observation

| ID | Class | Code evidence | Recommended wording | Migration effect | Detailed owner |
| --- | --- | --- | --- | --- | --- |
| INV-P01 | Changed | `Jido.Persistence` validates `Jido.PortableTerm`; Agent transition does not enforce it. | Every value that crosses into a checkpoint or persistence record contains no PID, port, reference, function, improper list, or non-byte-aligned bitstring. Seam 01 and seam 12 decide if all live Agent state must meet this rule earlier. | Keep current persistence rejection. Add earlier validation only with error and compatibility rules. | 01, 07, and 12 |
| INV-P02 | Retained | Public structs have schemas; some protocol results are documented maps. | Each shaped public success value has one owner and one purpose. Do not add a struct before its owner and migration are clear. | Audit proposed types before implementation. | 12 and each value owner |
| INV-P03 | Changed | `Jido.Error` has Splode types, but public boundaries also return atoms and tuples. | Public construction, command, and lifecycle failures use owner-defined Splode errors, except for protocol results that seam 12 lists explicitly. | Add codes and normalization without breaking all tuple controls at once. | 12 |
| INV-P04 | Deferred | Current status, snapshot, telemetry, and OTP controls use maps or tuples. | Raw maps and OTP control values are allowed only as explicit documented protocol exceptions. | Seam 12 must inventory the exceptions and migration path. | 12 |
| INV-P05 | Retained | `test/jido/observe/agent_lifecycle_test.exs` | Direct `Agent.cmd/3` emits no Agent runtime telemetry. | None. | 04 and 13 |
| INV-P06 | Retained | `lib/jido/telemetry/agent.ex`; observation tests | The live Turn result span stops at the commit and live-result boundary. | Preserve event order. | 08 and 13 |
| INV-P07 | Retained | Semantic Directive spans and tests | Directive work uses separate post-commit spans and one later terminal settlement event. | Preserve behavior. | 06, 08, and 13 |
| INV-P08 | Retained | Telemetry handlers are contained; observation tests prove unchanged results. | Observation cannot change an Agent result or runtime outcome. | Preserve handler isolation. | 13 |
| INV-P09 | Retained | `lib/jido/telemetry/agent.ex`; bounded metadata tests | Semantic telemetry metadata contains no Agent state, Plugin state, payload, caller context, process handle, or raw error detail. | Keep bounded metadata in all new events. | 13 |

## 6. Vocabulary reconciliation

Use these preferred terms in later design documents.

| Preferred term | Meaning | Do not use as an alias |
| --- | --- | --- |
| Agent definition | An immutable static Agent value with schema, routes, Plugin declarations, and metadata, but no instance ID or state. | Agent class, Agent template |
| Agent instance | An immutable Agent value with an ID and complete validated state. | live Agent, actor process |
| Agent ID | The current nonempty string inside one Agent instance. | Ref, PID |
| Agent Ref | The proposed stable identity across lookup, storage, and delivery. It is separate from location. | PID, server name, persistence key |
| Runtime handle | A PID or OTP name that addresses the current activation. | Agent identity |
| Source Signal | The Signal received for the Turn. It never changes. | original event, raw command |
| Effective Signal | The bounded Signal view after allowed admission or preparation changes. It does not select another executable. | rewritten source Signal |
| Turn | One fixed Action or Flow selection and its input for one source Signal. | transaction, job |
| Executable | The selected Action or Flow. | handler, route result |
| Candidate Agent | The complete validated immutable Agent proposed by evaluation. | next live state, commit |
| Evaluation return | The direct `Agent.cmd/3` result. It proves no live or durable commit. | Result, Outcome |
| Live result | The tagged reply from live command execution at the commit boundary. | Result struct, Turn Outcome |
| State version | The integer that advances once for each successful live Turn commit. | storage lease, definition revision |
| Commit | The operation that makes one candidate Agent live after required persistence succeeds. | candidate, persistence write |
| Turn Outcome | The terminal observation after Directive work settles or the Turn otherwise stops. | live result, commit result |
| Directive | A typed request for runtime-owned post-commit work. | guaranteed durable effect |
| Durable work intent | Portable pending work with a stable operation ID in Agent or Plugin state. | Directive queue, universal outbox |
| Runtime checkpoint | The nondurable in-instance snapshot used for abnormal nonpersistent Server restart. | durable record, initial Agent |
| Agent checkpoint | Portable reconstruction data produced by the Agent persistence boundary. | runtime checkpoint, Codec document |
| Persistence record | The durable lifecycle and compare-and-swap envelope. The current form is a private map. | Agent identity, checkpoint |
| Write authority | Permission for the current activation to perform another durable commit. | PID ownership, Registry presence |
| Definition revision | A module-owned revision of normalized Agent definition meaning. It does not by itself pin loaded BEAM code. | state version, package version |
| Plugin | The user-declared reusable capability. Current code also uses this name for one mixed behavior. | adapter, authoring extension |
| Plugin facet | A proposed owner-specific Plugin behavior. | arbitrary hook, adapter |
| Plugin runtime | Supervised resources for one Plugin on one Agent activation. | Plugin state |
| Jido instance | One named local supervision and service boundary. | namespace, cluster |
| Runtime topology | The OTP process and ownership layout below a Jido instance. | Topology definition |
| Topology control plane | Static desired definitions, plans, repair, and any future live target management. | Agent pool |
| Adapter | A replaceable external service boundary. | Plugin facet |
| Authoring extension | Static syntax lowering to canonical values. | runtime Plugin |

Do not use `%Jido.Plugin{}` as a public configuration struct. It does not
exist. Do not use `Result` as the name of an unapproved new value. Do not say
that all Agent evaluation is pure, because Actions and Flows can perform I/O.
Do not say that a nonpersistent restart uses the initial Agent. Do not describe
Builder, Codec, owned children, PID APIs, or local debug as removed.

## 7. Design and code conflict decisions

These dispositions cover the material conflicts and missing-contract pressure
points in `gap-analysis.md`. They are recommendations until the user approves
them.

| Conflict or pressure point | Disposition | Reason | Execution owner |
| --- | --- | --- | --- |
| Plugin preparation currently occurs before route selection. | Change | Fix selection from the source Signal before preparation. This gives one stable Turn executable. | 04 and 05 |
| Current routing rejects multiple matches. | Change | Use the Router's existing precedence and select the first target. | 04, with `jido_signal` compatibility evidence |
| Plugins see the complete Agent and share one prepared command. | Change | Add declared observation and isolated prepared input. Keep declaration order. | 01, 04, and 05 |
| The overview says that nonpersistent restart resets to the initial Agent. | Remove | Current runtime checkpoints preserve the last commit and a focused test requires it. | 08, 09, and 10 update their documents |
| The overview says that all runtime effects start after commit. | Change | Only Directive work has that rule. Action and Flow I/O can occur before commit. | 06 |
| `architecture.md` lists `%Jido.Plugin{}` as a public configuration struct. | Remove | `Jido.Plugin` is a behavior. The current normalized Spec is private. | 05 decides a manifest and facet model |
| Core has no stable Agent Ref. | Change, staged | Stable identity is useful across Registry, persistence, and delivery, but it must not remove PID APIs immediately. | 03, 07, 09, and 10 |
| Core has no positive definition revision. | Change, staged | Restore and upgrade need explicit definition identity. A label does not by itself pin executable code. | 01, 02, 04, and 07 |
| Proposed Checkpoint, Commit, Record, Status, Turn Status, Plugin Context, Plugin Transition, Plugin Contribution, and Instance Config structs do not exist. | Defer exact shapes | Overview defines roles only. Each owner must show a need, migration, serialization, and error contract. | 01, 05, 07, 08, 09, and 12 |
| The current live result is a tagged tuple, but `architecture.md` can imply a new Result value. | Remove the implied struct | Keep the tagged live result. Keep Turn Outcome as terminal observation. | 08 and 12 |
| Plugin runtime Init lacks committed Plugin state and state version. | Change | Replacement must start from one coherent committed snapshot. Keep the state-pull API during migration. | 05, 08, and 10 |
| Confirmed persistence errors can leave a writable Server alive. | Change | A failed write means the activation does not have proof that it can continue safely. | 07 and 08 |
| Persistent startup does not write an initial active record. | Change | Durable creation needs one clear readiness and publication boundary. | 07, 08, and 10 |
| Durable delete removes revision history. | Change | A compare-and-swap tombstone prevents a delayed initial writer from recreating a deleted Agent. | 07 |
| Old proposals remove Builder and Codec. | Remove the removal proposal | Both APIs are documented, tested, and use shared validation. | 01 and 02 preserve them |
| Old proposals remove public PID APIs immediately. | Defer any removal | PID APIs are documented and tested. Add Ref-first APIs beside them before any deprecation decision. | 03, 08, 09, and 12 |
| The four Plugin facets are proposed but not implemented. | Defer detailed contract; recommend the ownership model | The current behavior mixes pure Agent work and live Server work. Exact callbacks and checkpoint interaction belong to seam 05. | 05, with 01 and 07 |
| The combined Topology authoring host exists, but its owner Agent does not own the live target. | Retain authoring; defer runtime ownership | Current Controller behavior is useful and tested. A control-plane owner and live updates need a separate contract. | 11 |
| Plugin wrappers share the Agent Dynamic Supervisor. | Defer physical pool change | Overview requires separate logical roles, not an unproved supervision layout. | 09 and 10 |
| Legacy `:agent_server` telemetry, Observe tracer, and debug paths coexist with semantic events. | Retain during migration | These are supported compatibility paths. Seam 13 can define deprecation only after replacement coverage exists. | 13 |
| Per-Agent persistence override exists, while one instance-only provider is proposed. | Defer | Both are public planning inputs. Package boundaries and instance policy must decide compatibility first. | 90, 07, and 09 |
| Durable, cluster, and fabric package names appear as future owners. | Retain as boundary direction; defer APIs | Core is local. No external package contract is complete without an integration proof. | 90 and 99 |

## 8. Ordered documentation and implementation alignment phases

The phases follow the dependency graph in `docs/design/AGENTS.md`. Each phase
first aligns documents. Runtime work starts only after the needed contracts are
approved.

| Phase | Shared contract change | Affected later seams | Compatibility effect | Evidence | Exit criteria |
| --- | --- | --- | --- | --- | --- |
| 1. Approve the overview baseline | Replace mixed current and deferred claims with the model, vocabulary, and invariant dispositions in this plan. | All | No runtime change. | This alignment, the gap analysis, and the canonical paths in section 2. | User approves the requested decisions. Overview source documents are updated to match. |
| 2. Lock package and public-boundary policy | Confirm lower-layer direction, extension categories, core-local scope, supported API retention, and protocol exceptions. | 90, then 12 | Builder, Codec, PID APIs, owned children, adapters, and debug remain available during migration. | `mix.exs`, `guides/core-scope.md`, `guides/extension-boundaries.md`, public API tests. | Seam 90 alignment is approved. Seam 12 has a fixed owner and compatibility inventory. |
| 3. Align errors and value ownership | Define stable public error classes, codes, normalization, and rules for new structs versus documented maps and tuples. | 12, then 01 and all API seams | New errors and values are additive until callers have migration evidence. | Error, transport, status, snapshot, and Outcome tests. | Seam 12 alignment is approved. Every later seam can name its result and error owner. |
| 4. Align Agent, authoring, identity, and Turn | Keep the immutable Agent and all authoring forms. Add the approved definition revision and stable Ref direction. Fix source-Signal route selection and direct/live parity. | 01, then 02, 03, and 04 | Route ambiguity and route-changing Plugins need migration notes. Builder, Codec, neutral definitions, custom routing, and PID handles remain supported. | Agent, Builder, Codec, route, stable-reference, definition-revision, and Turn tests. | Seams 01 through 04 have approved alignments. FA-01, FA-03, and FA-04 have passing or explicitly deferred acceptance proof. |
| 5. Align Plugin ownership | Decide the facet model, declared observation, prepared-input isolation, owned state, and coherent runtime replacement input. | 05 | Keep the ordered Plugin declaration form. Use adapters and compatibility delegates for callback migration. | Plugin contract tests, FA-02, and FA-06. | Seam 05 alignment is approved. Plugin checkpoint interaction is explicit. Isolation and replacement proofs pass or are explicitly deferred. |
| 6. Align commit, effects, and durability | Keep one commit point and post-commit Directive work. Define write-authority loss, initial durable creation, record lifecycle, and tombstones. | 06, then 07 | Persistence record and delete behavior change. Existing adapter compare-and-swap stays. | Commit and Directive tests, persistence conflict and indeterminate tests, portability tests, FA-05. | Seams 06 and 07 are approved. Create, commit, restore, conflict, uncertain write, delete, purge, and reactivation each have an owned contract. |
| 7. Align live ownership and runtime topology | Apply approved identity, durability, Plugin, and error rules to Agent Server, Jido instance, and process ownership. Keep nonpersistent runtime-checkpoint restore. | 08, then 09 and 10 | Ref-first APIs are additive. PID APIs remain for a stated period. Any pool change must preserve restart behavior. | Public API, instance, supervisor, runtime lifecycle, child ownership, and distributed tests. | Seams 08 through 10 are approved. Restart sources, readiness, pool roles, and local resolution are proven. |
| 8. Align Topology control and observation | Keep static local repair. Decide owner-Agent runtime and live target scope. Make semantic events primary and plan legacy-path migration. | 11, then 13 | No current Topology or observation API is removed without a staged plan. | Topology controller, composition, authoring-host, telemetry, and observation tests. | Seams 11 and 13 are approved. Any live topology or legacy removal item has explicit acceptance proof or is deferred. |
| 9. Close delivery | Combine approved seams into release scope and migration order. | 99 | Release notes state every additive, changed, deprecated, and deferred contract. | Full core quality, examples, cross-package V3 tests, and migration probes. | Delivery plan is approved and all required acceptance gates pass. |

## 9. Downstream planning gates

After this plan is approved, later seams can rely on the decisions below. They
must not treat the listed open details as approved.

| Seam | Decisions it can rely on | Detailed decisions that remain open |
| --- | --- | --- |
| 90 Package boundaries | Jido is the local coordination layer above `jido_action` and `jido_signal`. Adapters, Plugin facets, authoring extensions, Directives, and tracers are different categories. Supported APIs need staged migration. | Exact future package APIs, per-Agent persistence override, and public extension functions. |
| 12 Errors and contracts | Each public value and error has one owner. Live result and Turn Outcome are different. Maps and OTP values can be documented protocol exceptions. | Exact structs, codes, fields, normalization matrix, and exception inventory. |
| 01 Agent | Agent definitions and instances are immutable. Direct `cmd/3` returns a candidate and Directives. Domain and Plugin state have separate write owners. Agent values contain no runtime handles. Builder and Codec stay. | Physical state layout, public state operations, checkpoint shape, definition-revision field rules, and compatibility details. |
| 02 Agent authoring | DSL, direct definitions, Builder, Codec, and inline Actions remain valid authoring categories and must reach one normalized definition contract. | Revision syntax, Codec version migration, DSL details, and extension APIs. |
| 03 Agent identity | A PID is only a runtime handle. Stable identity, location, and write authority are different questions. A Ref-first migration must keep current APIs during transition. | Ref fields, partition type, namespace binding, storage-key migration, and transport behavior. |
| 04 Turn evaluation | One Turn fixes one executable. Direct and live paths share candidate evaluation. Recommended routing uses first Router match from the source Signal before preparation. | Effective-Signal fields, custom callback migration, prepared-input shape, timeout, and code-revision pinning. |
| 05 Plugins | A Plugin is a declared capability. Owned state, pure Agent work, live Server work, persistence conversion, and topology planning have different owners. Declaration order stays stable. | Approval and exact shape of four facets, callback signatures, observation declarations, merge rules, and custom checkpoint interaction. |
| 06 Commit and effects | One live commit follows validation and required persistence. Directive work is post-commit. Action and Flow I/O can occur pre-commit. Core has no universal durable outbox. | Commit value shape, Directive batch policy, cancellation boundary details, and durability guarantee levels. |
| 07 Persistence | Keep binary adapters and atomic compare-and-swap. Recommended target adds initial active records, lost write authority on every write error, and tombstones. | Record struct, revisions versus storage tokens, timeout, retention, purge, reactivation, and per-Agent provider policy. |
| 08 Agent Server | The Server is the serialized live owner. One commit increments the state version once. Nonpersistent abnormal restart restores the latest in-instance runtime checkpoint. PID APIs remain during migration. | Ref-first methods, status structs, timeout rules, write-error stop form, and startup publication protocol. |
| 09 Jido instance | The instance owns local services, lookup, supervision, Runtime Store, and live persistence context. | Namespace configuration, facade surface, supervisor strategy, pool split, and provider override policy. |
| 10 Runtime topology | Agent Servers are peers. Plugin runtimes are capability resources. Replacement uses current committed Plugin state and version. | Physical pools, restart coupling, readiness task ownership, remote Ref resolution, and placement policy boundaries. |
| 11 Topology control plane | Current static definition, plan, local Controller, readiness, and repair stay supported. Authoring-owner values do not prove runtime ownership. | Owner runtime, desired-state storage, `start_topology`, live target update, rolling upgrade, and resumability. |
| 13 Observability | Semantic lifecycle, Turn, commit, Directive, and settlement boundaries are the target. Metadata stays bounded and observation cannot change outcomes. | Event inventory, metrics, persistence events, OpenTelemetry bridge, and retirement schedule for legacy telemetry, tracer, and debug paths. |
| 99 Delivery | Work follows the dependency order in section 8. A supported API is not removed without a decision, migration period, and evidence. | Release cut, required versus deferred upgrades, version matrix, and final rollout schedule. |

## 10. Cross-seam acceptance matrix

This matrix maps every reconciled invariant group to current proof or required
future proof. A skipped test is a specification, not passing proof.

| Target IDs or boundary | Current proof | Required future proof |
| --- | --- | --- |
| INV-T01 and INV-T05 | `test/jido/agent_server/public_api_test.exs`; `test/examples/99_research/99_09_route_selection/route_selection_test.exs` single-route case | Keep direct/live parity in the final Turn suite. |
| INV-T02 through INV-T04 | Router precedence is implemented in `../jido_signal`; Jido exact-one behavior is tested in `test/jido/agent_test.exs`. | Enable both FA-01 tests. Add exact, `*`, `**`, predicate, priority, and declaration-order cases for direct and live paths. |
| INV-T06 through INV-T09, INV-T11, and INV-T12 | `test/jido/plugin/contract_test.exs` proves state ownership, Directive filtering, order, and candidate validation. | Repeat these proofs through any facet compatibility layer. |
| INV-T10 | Current tests prove the gap only. | Enable both FA-02 tests. Prove declared observation, isolated input, deterministic merge, and direct/live parity. |
| INV-C01 through INV-C03 | `test/jido/agent_server/public_api_test.exs`, `test/jido/agent_server/directive_execution_test.exs`, and `test/jido/persistence_test.exs` | Add equal-state success and paired pre-commit failure revision proof if not already explicit. Keep Action-I/O documentation tests or examples. |
| INV-C04 through INV-C08 | `test/jido/plugin/scheduler/occurrence_recovery_test.exs` and Scheduler durable tests | Keep stable ID, retry, acknowledgement, restart, and unrelated-Turn preservation proof. |
| INV-C09 | Persistence adapter and stale-writer tests | Run the same adapter contract for each supported adapter and compatible V3 package set. |
| INV-C10 and INV-C11 | `test/jido/persistence/indeterminate_write_test.exs` proves uncertain-write stop. `test/jido/persistence_test.exs` proves current confirmed-conflict continuation. | Add a matrix for conflict, confirmed adapter error, exception, timeout, and indeterminate result. Prove no later evaluation before reload. |
| INV-C12 | `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs` proves the current gap. | Enable FA-05. Add retention, purge, reactivation, stale writer, and rollback cases. |
| INV-D01 and INV-D02 | Definition revision example proves same-definition restore; mismatch proof is skipped. | Enable FA-04. Add Builder, Codec, neutral definition, custom checkpoint, and old-record migration cases. |
| INV-D03 and INV-D04 | Instance and startup tests prove ID and PID replacement behavior. Stable-reference tests use an application substitute. | Add core Ref construction, serialization, Registry, persistence, Directive, node-move, and stale-location proofs. Enable FA-03. |
| INV-D05 | Persistence restore, thaw, and Controller restore tests | Preserve latest-record restore with the new Record lifecycle. |
| INV-D06 | `test/jido/agent_server/runtime_lifecycle_test.exs` proves last-commit restore after abnormal restart. | Add full-instance-stop proof that the nondurable checkpoint is gone. |
| INV-D07 and INV-D08 | Instance persistence selection and Plugin readiness are tested. Initial record is absent. | Prove provisional readiness, revision-zero write, publication, cleanup on readiness/write failure, and configured provider authority. |
| INV-R01 and INV-R02 | `test/jido/supervisor_test.exs`; Plugin lifecycle tests | If pools change, prove peer Agent behavior, Plugin isolation, and required restart cascade. |
| INV-R03 | Runtime lifecycle tests prove fresh state through the public pull API. FA-06 is skipped. | Enable FA-06 and prove state/version coherence for every replacement cause. |
| INV-R04 | Checkpoint portability and runtime lifecycle tests | Add one cross-boundary negative matrix for all proposed durable and runtime values. |
| INV-R05 through INV-R07 | Agent Server cancellation and runtime-boundary tests; caller timeout is documented. | Add a Turn-timeout matrix only if the feature is approved. Prove commit and Directive non-cancellation. |
| INV-R08 | Plugin runtime and Scheduler tests | Preserve Signal reentry and mailbox serialization through facet migration. |
| INV-P01 | `test/jido/persistence/checkpoint_portability_test.exs` | Decide and test whether rejection occurs only at checkpoint creation or also at Agent transition. |
| INV-P02 through INV-P04 | Current struct schemas, error tests, status maps, snapshots, and public API tests | Add the seam-12 value and error inventory. Test every public entry and documented protocol exception. |
| INV-P05 through INV-P09 | `test/jido/observe/agent_lifecycle_test.exs`; `test/jido/telemetry/agent_test.exs` | Add persistence, admission, topology, and any new Ref metadata cases. Keep legacy compatibility tests until retirement. |
| Package direction | `mix.exs`, public lower-layer documentation, and `guides/extension-boundaries.md` | Compile and test a declared compatible V3 matrix. Do not use an uncommitted sibling as proof for a Hex dependency. |
| Topology ownership boundary | Topology composition, authoring-host, Controller readiness, repair, and state-retention tests | Add owner desired-state and live-target tests only after seam 11 approves those contracts. |

## 11. Open decisions that need user approval

Each item is small enough for a direct decision.

1. **A-01, route contract.** Recommended: select the first Router match from
   the source Signal before Plugin preparation. Admission and preparation must
   not change that executable. Effect: deterministic fallback routes replace
   the current multiple-match error, and route-changing Plugins need migration.
2. **A-02, nonpersistent restart.** Recommended: retain the current
   in-instance runtime checkpoint. An abnormal Server restart restores the last
   committed Agent and state version. Effect: remove the reset-to-initial text
   from the overview and later seams.
3. **A-03, stable identity scope.** Recommended: make a stable Agent Ref a V3
   core target, separate from PID and location, and add it beside current ID and
   PID APIs. Effect: seams 03, 07, 09, and 10 must plan a staged migration. Exact
   fields remain with seam 03.
4. **A-04, definition revision.** Recommended: require a positive module-owned
   revision for module-authored definitions, preserve it through Builder and
   Codec, and define a legacy rule for old checkpoints. Effect: restore can
   reject definition mismatch, but full executable code pinning stays open.
5. **A-05, Plugin ownership model.** Recommended: approve the four owner
   categories in principle: Agent, Agent Server, Persistence, and Topology
   facets under one declared Plugin package. Effect: seam 05 can design a staged
   split of the current mixed behavior without changing the user declaration
   order.
6. **A-06, custom checkpoint compatibility.** Recommended: retain complete
   Agent `checkpoint/2` and `restore/2` callbacks during V3. A Persistence facet
   must not silently override them. Effect: seams 01, 05, and 07 must define one
   explicit composition or defer Persistence facets.
7. **A-07, durability release scope.** Recommended: require initial active
   records, loss of write authority after every write error, and tombstone
   deletion for V3. Effect: seams 07 and 08 have required behavior changes and
   migration tests.
8. **A-08, compatibility APIs.** Recommended: retain Builder, Codec, neutral
   definitions, owned children, public PID Agent Server APIs, and local debug
   paths for the V3 release. Effect: new Ref, value, Plugin, and semantic
   telemetry APIs are additive. Later removal needs a separate deprecation
   decision.
9. **A-09, Topology release scope.** Recommended: keep static local Topology
   activation and repair in V3. Defer owner-Agent control of live desired state
   and live target updates until seam 11 proves them. Effect: the current
   Controller stays the supported runtime and live upgrade does not block V3.
10. **A-10, package boundary.** Recommended: keep core local. Treat durable,
    cluster, and fabric packages as future owners for recovery services,
    cluster policy, and transport. Effect: no unproved package API becomes a V3
    dependency.
11. **A-11, public value rollout.** Recommended: approve value roles in this
    overview, but defer exact new struct sets to seam 90, seam 12, and each value
    owner. Effect: current maps, tuples, and structs stay canonical until a
    staged replacement is approved.
12. **A-12, legacy observation.** Recommended: make semantic Agent events the
    target and retain `:agent_server` telemetry, `Jido.Observe`, and debug paths
    during migration. Effect: seam 13 must supply replacement coverage and a
    separate deprecation plan before removal.
