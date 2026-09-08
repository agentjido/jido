> Seam alignment plan. This document is pending approval.

# Core model, shared terms, and invariants alignment

## Status

- Design reviewed: 2026-09-08. The design review index contains no approved
  Overview entry.
- Code reviewed: `4e63640efd499ee2df3c717016e8d3542376f1b2`.
- Prerequisite alignments: None. This is the first alignment gate.
- Alignment state: `Draft`.
- Approved decisions: None. The review-status table in
  `docs/design/README.md` is the source of truth.

The alignment state is execution status. It is not document approval. This
document records current evidence and recommended dispositions. It does not
change runtime behavior.

## Inputs and evidence

### Design

- `docs/design/AGENTS.md`: review, EARS, dependency-order, and document-pattern
  rules.
- `docs/design/SEAM_TEMPLATE.md`: required three-file seam structure.
- `docs/design/VISION.md`: the pending Jido V3 Bright Line and library vision.
- `docs/design/README.md`: design order and canonical approval status.
- `docs/design/00_overview/design.md`: recommended shared target.

### Canonical code

| Evidence path | Canonical current behavior |
| --- | --- |
| `lib/jido/agent.ex:2-21` | An Agent is immutable data. A direct command returns a candidate Agent and Directives and does not commit live state. Plugin preparation occurs before routing. |
| `lib/jido/agent.ex:370-423` | Agent modules can own complete checkpoint and restore callbacks. Default checkpoints are maps with no definition revision. |
| `lib/jido/agent.ex:458-477` | `cmd/3` delegates to the Runner. Default routing requires exactly one executable Turn. |
| `lib/jido/agent/command/runner.ex:29-132` | Direct and live execution share the Runner. Plugin preparation occurs before route selection, state protection, Plugin reduction, and candidate validation. |
| `lib/jido/agent/command/runner.ex:178-227` | Jido rejects multiple Router targets and normalizes routing failures. |
| `lib/jido/agent/command.ex:1-22` | The current public Plugin preparation input contains the complete Agent, Signal, and caller context. |
| `lib/jido/plugin.ex:2-24` | One Plugin behavior combines admission, pure preparation, owned state, Directives, dispatch, and runtime work. |
| `lib/jido/plugin.ex:67-102` | Current callback contracts use `Jido.Agent.Command`, Plugin Init, and Directive and Signal contexts. |
| `lib/jido/plugin.ex:190-205` | Live Plugin admission is serial in declaration order. |
| `lib/jido/plugin.ex:238-265` | Executable writes to Plugin state are rejected. Plugin runtime children use `Jido.Plugin.Init`. |
| `lib/jido/plugin.ex:797-875` | A Plugin cannot replace the Agent. Plugin state reduction is ordered and receives only owned Directives. |
| `lib/jido/plugin/init.ex:1-19` | Runtime Init has a Server PID and Agent ID, but no committed Plugin state or state version. |
| `lib/jido/plugin/scheduler.ex:30-48` | Scheduler documents durable pending work, acknowledgement, and the bounded `delivery_interval` option. |
| `lib/jido/plugin/scheduler/runtime.ex:415-436` | Scheduler applies `delivery_interval` between pending-work attempts. |
| `lib/jido/agent_server.ex:2-42` | The Agent Server owns serialized live Turns, one commit, ordered Directives, and state-version rules. Executable I/O can occur before commit. |
| `lib/jido/agent_server.ex:257-309` | Status is a map. Lookup uses Agent ID and partition and returns a PID. |
| `lib/jido/agent_server.ex:381-389` | Snapshot is a map with the Agent and state version. |
| `lib/jido/agent_server.ex:506-544` | Plugin runtimes become ready before startup reports success. No initial durable write occurs at this boundary. |
| `lib/jido/agent_server.ex:1285-1309` | Live admission runs before shared Runner preparation and can change the command Signal. |
| `lib/jido/agent_server.ex:1419-1545` | The Server uses Runner preparation and completion, persists first, installs the candidate, replies, and then starts Directives. |
| `lib/jido/agent_server.ex:1548-1594` | An uncertain persistence write always stops the Server. Other write failures can use a continuing error policy. |
| `lib/jido/agent_server.ex:1639-1756` | Directives are validated before commit and handled after commit. A Directive failure has its own terminal result. |
| `lib/jido/agent_server.ex:1878-1923` | Public status and active-Turn views are maps. |
| `lib/jido/agent_server.ex:2882-2929` | Nonpersistent startup uses Runtime Store state. Persistent startup loads a durable record. Commits use the current state version as the expected revision. |
| `lib/jido/agent_server/runtime_checkpoint.ex:8-50` | A named instance restores the last nondurable Agent and version after abnormal Server restart and deletes the checkpoint on a clean stop. |
| `lib/jido/agent_server/plugin_lifecycle.ex:9-39` | Plugin runtime startup and readiness are owned by the Agent Server lifecycle. |
| `lib/jido/agent_server/plugin_lifecycle.ex:110-198` | Plugin wrappers use the Jido Agent Dynamic Supervisor and remain outside Agent state. |
| `lib/jido/agent_server/options.ex:11-64` | Agent Server options include an optional per-Agent persistence source and current map-based runtime options. |
| `lib/jido/persistence.ex:1-16` | Persistence owns record keys, encoding, validation, and adapter fault containment. |
| `lib/jido/persistence.ex:59-159` | Persistence uses atomic revision checks, instance/module/partition/ID keys, and physical delete. |
| `lib/jido/persistence.ex:285-315` | Current checkpoints and records are maps. Persistence rejects nonportable records. |
| `lib/jido/persistence/adapter.ex:1-46` | Adapters store bytes and provide atomic compare-and-swap. They do not own lifecycle policy. |
| `lib/jido.ex:8-48` | Jido exposes immutable Agent and direct-command concepts and public PID-based instance examples. |
| `lib/jido.ex:129-169` | Instance configuration and public Agent operations use keyword lists, Agent IDs, and PIDs. |
| `lib/jido.ex:346-370` | A Jido instance starts one Task Supervisor, Registry, Runtime Store, Spawn Registry, and Agent Dynamic Supervisor. |
| `lib/jido/topology.ex:1-15` | Topology supports static definitions, shared constructors, and a combined Agent and Topology authoring host. |
| `lib/jido/topology/controller.ex:1-24` | The Controller owns static local activation and automatic or manual repair, not live target updates or cluster policy. |
| `lib/jido/topology/controller.ex:73-90` | Status, readiness, and manual reconcile use the existing target. |
| `lib/jido/error.ex:1-17` | Jido defines six consolidated Splode error types. |
| `lib/jido/telemetry.ex:8-30` | Semantic events separate lifecycle, Turn, commit, Directive, and settlement. Legacy Agent Server events remain. |
| `lib/jido/telemetry/agent.ex:8-44` | Semantic identity metadata is bounded and uses selected fields. |
| `lib/jido/telemetry/agent.ex:96-147` | The Turn span ends at commit. One later event reports terminal settlement. |
| `../jido_action/lib/jido_exec.ex:1-18` | `jido_action` owns the public Action, Instruction, and Flow execution boundary. |
| `../jido_signal/lib/jido_signal/router.ex:1-16` | `jido_signal` owns route precedence. |
| `../jido_signal/lib/jido_signal/router.ex:297-318` | The Router returns all matching targets in precedence order. |
| `../jido_signal/lib/jido_signal/router/index.ex:95-103` | Route lookup applies predicates, sorts by precedence, and returns ordered targets. |
| `mix.exs:351-360` | This checkout uses a sibling path for `jido_action` and a Hex V3 requirement for `jido_signal`. |

### Tests and examples

| Evidence path | Behavior proved or specified |
| --- | --- |
| `test/jido/agent_test.exs:157-389` | Definitions, instances, direct Turns, complete state validation, and checkpoint round trips work without a Server. |
| `test/jido/agent_test.exs:581-858` | Current routing, errors, context, Directives, direct determinism, and Flow execution are covered. |
| `test/jido/agent_test.exs:904-989` | Direct definitions and custom checkpoint and restore callbacks remain supported. |
| `test/jido/agent/builder_test.exs:19-65` | Builder route validation, order, reuse, and error retention are supported. |
| `test/jido/agent/codec_test.exs:29-67` | Codec route round trips and errors are supported. |
| `test/jido/plugin/contract_test.exs:490-670` | Plugin order, owned Directive filtering, state validation, and state-write protection are proved. |
| `test/jido/agent_server/public_api_test.exs:87-181` | One complete state commit, neutral definition startup, input separation, and live execution are proved. |
| `test/jido/agent_server/public_api_test.exs:230-305` | Action continuation, Flow execution, responsiveness, and state-version behavior are proved. |
| `test/jido/agent_server/public_api_test.exs:333-459` | Caller timeout, pre-commit failure, and cancellation behavior are proved. |
| `test/jido/agent_server/directive_execution_test.exs:27-184` | Directive validation, post-commit order, failure, timeout, and commit retention are proved. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:152-180` | Plugin runtime handles stay outside Agent state and stop with the Agent. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:225-289` | Plugin runtime replacement can pull current committed state and remain responsive. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:293-326` | Abnormal nonpersistent restart restores the last commit and state version. |
| `test/jido/persistence_test.exs:259-347` | Each successful live commit is saved. A stale Server cannot commit or dispatch, but it can remain running after a confirmed conflict. |
| `test/jido/persistence_test.exs:395-503` | Current physical delete and compare-and-swap conflict behavior are proved. |
| `test/jido/persistence/indeterminate_write_test.exs:35-93` | An uncertain write stops stale evaluation and blocks Directive handling. |
| `test/jido/persistence/checkpoint_portability_test.exs:15-45` | Portable values round trip and nonportable checkpoints are rejected. |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-212` | Saved work intent, retry, acknowledgement, and restart recovery are proved for Scheduler. |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs:175-195` | A focused recovery test proves that `delivery_interval` controls retry cadence without changing pending work. |
| `test/jido/topology/controller_test.exs:20-330` | Static activation, local repair, readiness, ownership, state retention, and cleanup are proved. |
| `test/jido/topology/authoring_host_test.exs:79-272` | The combined Agent and Topology authoring host is implemented and validated. |
| `test/jido/observe/agent_lifecycle_test.exs:10-45` | Direct evaluation emits no runtime events. Handler failure does not change the result. |
| `test/jido/observe/agent_lifecycle_test.exs:48-302` | Terminal Outcomes, commit boundaries, lifecycle events, and bounded metadata are proved. |
| `test/jido/error/normalization_test.exs:8-321` | Error constructors and public normalization are covered. |
| `test/examples/99_research/99_09_route_selection/route_selection_test.exs:6-37` | Direct and live parity is proved for one route. The target first-match and source-Signal cases are skipped. |
| `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:6-34` | Current Plugin state ownership is proved. Declared-view and prepared-input isolation cases are skipped. |
| `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:21-80` | An application-level stable reference works locally. Core durable namespace rebinding is skipped. |
| `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:16-27` | Same-definition restore works. Revision-mismatch rejection is skipped. |
| `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:13-31` | Current compare-and-swap and delete work. Tombstone fencing is skipped. |
| `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:14-43` | State-pull reconstruction works. State-and-version Init is skipped. |

### Prior validation record

The superseded Overview evidence recorded these results on 2026-09-08:

- Focused Agent, Plugin, persistence-authority, and observation tests: 94
  tests, zero failures.
- Selected research examples: 10 passing implemented controls, eight skipped
  target-contract cases, and zero failures.

The commands were:

```sh
mix test test/jido/agent_test.exs test/jido/plugin/contract_test.exs \
  test/jido/persistence/indeterminate_write_test.exs \
  test/jido/observe/agent_lifecycle_test.exs --seed 0

mix test test/examples/99_research/99_03_input_resource_lifecycle \
  test/examples/99_research/99_09_route_selection \
  test/examples/99_research/99_10_plugin_isolation \
  test/examples/99_research/99_11_stable_reference \
  test/examples/99_research/99_12_definition_revision \
  test/examples/99_research/99_13_durable_delete --include example --seed 0
```

This consolidation did not rerun tests because it changes design documents
only. A skipped test is a target specification, not passing evidence.

## Retained baseline

This section contains canonical current facts only. It does not state the
recommended target.

### Agent values and authoring

- `%Jido.Agent{}` is the immutable Agent definition or instance value. A
  definition has schema, routes, Plugins, and metadata. An instance adds a
  nonempty ID and complete state.
- Spark DSL, direct declarations, inline Actions, Builder, and Codec use the
  Agent validation boundary.
- `Jido.Agent.cmd/3` returns a candidate Agent and Directives. It starts no
  process, commits no live state, handles no Directive, and emits no Agent
  runtime telemetry.
- `%Jido.Agent.Command{}` and `%Jido.Agent.Turn{}` are current command and
  selection values. `%Jido.Agent.Turn.Outcome{}` is the current public terminal
  live-Turn value.
- Complete Agent `checkpoint/2` and `restore/2` callbacks are supported.

### Current Turn and Plugin path

The current path is:

```text
source Signal
  -> live Plugin admission, for live calls
  -> sequential Plugin prepare chain
  -> route the prepared Signal
  -> require exactly one matching target
  -> run one Action or Flow through Jido.Exec
  -> protect Plugin-owned state
  -> validate Directives
  -> reduce Plugin-owned state in declaration order
  -> validate one candidate Agent
```

- Admission and preparation can change the Signal. Route selection uses the
  changed Signal.
- The Signal Router returns all targets in precedence order. Jido rejects zero
  or multiple targets.
- A preparation callback receives the complete Agent, Signal, and caller
  context. All Plugins pass one command value through a serial chain.
- An Action or Flow returns the complete proposed state and can do synchronous
  external I/O. It cannot change a Plugin-owned state key.
- Each stateful Plugin owns at most one state key. Its reducer receives only
  Directives owned by that Plugin.
- Direct and live execution share the private Runner evaluation mechanism.

### Current commit and recoverable work

- One Agent Server serializes admission, evaluation, commit, and Directive
  handling for one activation.
- A successful Turn persists or checkpoints first, installs the complete
  candidate, increases `state_version` once, replies to the caller, and handles
  Directives in list order.
- A pre-commit failure preserves the committed Agent and version. A
  post-commit Directive failure preserves the commit and version.
- Jido does not undo external I/O that an Action or Flow completed before a
  failed commit.
- Ordinary Directive handling has no general crash-recovery guarantee.
- Scheduler is a proved capability-specific pattern. It stores portable work
  intent and stable occurrence IDs, retries saved work, and acknowledges
  completion through a later Signal and commit. Its `delivery_interval` option
  changes retry cadence without changing occurrence identity or pending work.

### Current runtime and instance boundary

- A PID, registered name, global name, or `:via` value addresses the current
  Agent Server. Instance helpers start, find, stop, hibernate, and thaw Agents
  by current IDs and return PIDs.
- A Jido instance starts a Task Supervisor, Registry, Runtime Store, Spawn
  Registry, and one Dynamic Supervisor for Agent Servers and Plugin wrappers.
- Plugin runtime handles stay in private Server state. They do not enter Agent
  state or checkpoints.
- `%Jido.Plugin.Init{}` has a Server PID, Agent ID, module, instance,
  partition, and options. It does not have committed Plugin state or a matching
  Agent state version.
- A nonpersistent named-instance Server stores its last commit in Runtime
  Store. An abnormal Server restart restores it. A clean full instance stop
  removes the nondurable state.

### Current persistence boundary

- Persistence uses private map records and portable map checkpoints. The
  record key includes Jido instance, Agent module, partition, and Agent ID.
- The Server uses the current state version as the expected revision for an
  atomic compare-and-swap write.
- An uncertain write always stops the Server. A confirmed conflict or adapter
  error can use the configured error policy and can leave the Server running.
- Persistent startup loads a record when one exists. It starts Plugin runtimes
  and waits for readiness. It does not write an initial active record.
- Delete removes the adapter value and its revision history. It writes no
  tombstone.
- A live Agent can inherit the instance persistence source or select an
  explicit per-Agent source.

### Current Topology, errors, observation, and package direction

- Static Topology definitions and plans are immutable. DSL, Builder, and Codec
  use common validation and planning.
- The local Controller supports startup, readiness, automatic repair, and
  `repair: :manual` with `reconcile/2`. Reconcile uses the existing target. It
  does not update desired state or transfer ownership.
- A Topology module has an authoring owner Agent, but that Agent does not own
  the live Controller target.
- `Jido.Error` defines six Splode errors. Some public protocols still return
  atoms, tuples, and maps.
- Semantic telemetry separates lifecycle, Turn, commit, Directive, and
  settlement boundaries. It excludes private state and payload data. Legacy
  Agent Server telemetry, `Jido.Observe`, tracing, and debug paths remain.
- `jido_action` owns executable work. `jido_signal` owns Signals and ordered
  route matching. `jido` owns Agent meaning, Plugin composition, live commit,
  local runtime, persistence policy, errors, and observation.

## Gap register

All dispositions in this table are recommendations. None are approved.

| Gap | Requirement | Current evidence | Difference | Recommended disposition |
| --- | --- | --- | --- | --- |
| `OVR-GAP-001` | `OVR-REQ-013` through `OVR-REQ-015` | `lib/jido/agent/command/runner.ex:64-90,178-193`; `test/examples/99_research/99_09_route_selection/route_selection_test.exs:23-37` | Preparation occurs before routing, and Jido rejects multiple matches. | `Change`: select the first source-Signal match before preparation. |
| `OVR-GAP-002` | `OVR-REQ-020` through `OVR-REQ-022` | `lib/jido/agent/command.ex:1-22`; `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:22-34` | A Plugin sees the complete Agent and shares one mutable prepared command. | `Change`: add declared views and isolated owned input. Preserve order and write protection. |
| `OVR-GAP-003` | `OVR-REQ-011` and `OVR-REQ-012` | `lib/jido/agent_server.ex:295-309`; `lib/jido/persistence.ex:153-159` | Core has no stable Agent Ref. Registry and persistence identity shapes differ. | `Change, staged`: add Ref-first contracts beside current ID and PID APIs. |
| `OVR-GAP-004` | `OVR-REQ-009` and `OVR-REQ-010` | `lib/jido/agent.ex:403-420,563-574`; `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:16-27` | Checkpoints have no enforced definition revision. Restore can use the loaded module definition. | `Change, staged`: add revision and old-checkpoint rules. Keep all authoring forms. |
| `OVR-GAP-005` | `OVR-REQ-040` | `lib/jido/agent_server.ex:506-533,2887-2905` | Persistent startup reports readiness without an initial active durable record. | `Change`: define provisional readiness, record write, publication, and cleanup in owner seams. |
| `OVR-GAP-006` | `OVR-REQ-039` | `lib/jido/agent_server.ex:1548-1594`; `test/jido/persistence_test.exs:305-347` | Only uncertain writes always remove the activation. Confirmed failures can continue. | `Change`: remove write authority after every write failure. |
| `OVR-GAP-007` | `OVR-REQ-042` | `lib/jido/persistence.ex:137-150`; `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:21-31` | Physical delete removes revision history, so a delayed initial writer can recreate data. | `Change`: use a compare-and-swap tombstone after retention and reactivation rules are set. |
| `OVR-GAP-008` | `OVR-REQ-048` | `lib/jido/plugin/init.ex:1-19`; `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:35-43` | Plugin runtime Init does not contain committed owned state or state version. | `Change`: add a coherent replacement input and keep state-pull compatibility. |
| `OVR-GAP-009` | `OVR-REQ-052`, `OVR-REQ-053`, and `OVR-REQ-065` | `lib/jido/agent_server.ex:257-263,381-389,1878-1923`; `lib/jido/error.ex:1-17` | Current public contracts use structs, maps, tuples, atoms, and partially normalized errors. | `Defer exact shapes`: seam 12 and value owners define the exception and migration inventory. |
| `OVR-GAP-010` | `OVR-REQ-005` | `lib/jido/plugin.ex:2-24,67-102` | One Plugin behavior mixes Agent, Agent Server, persistence-related state, and runtime concerns. | `Defer details`: approve owner categories first; seam 05 owns callbacks and migration. |
| `OVR-GAP-011` | `OVR-REQ-043` | `lib/jido/persistence.ex:285-315`; `test/jido/persistence/checkpoint_portability_test.exs:15-45` | Portability is checked at persistence encoding, not at every proposed value boundary. | `Defer boundary timing`: seams 01, 07, and 12 define where rejection occurs. |
| `OVR-GAP-012` | `OVR-REQ-060` and `OVR-REQ-061` | `lib/jido/topology/controller.ex:1-24,81-90`; `test/jido/topology/authoring_host_test.exs:79-272` | Static authoring and repair exist. Owner-Agent live control and target updates do not. | `Retain and defer`: keep static local Topology; do not make live control a V3 gate. |
| `OVR-GAP-013` | `OVR-REQ-014`, `OVR-REQ-021`, `OVR-REQ-009`, `OVR-REQ-011`, `OVR-REQ-042`, `OVR-REQ-048` | Six research example files in the evidence table | Eight target-contract tests are skipped. | `Change evidence state`: owner seams supply passing acceptance proof after approval. |
| `OVR-GAP-014` | `OVR-REQ-001` through `OVR-REQ-066` | Separate tests in the evidence table | No single executable conformance set maps all shared requirements to owner-seam evidence. | `Change evidence state`: seam 99 closes one traceable cross-seam acceptance set. |
| `OVR-GAP-015` | `OVR-REQ-001` through `OVR-REQ-066` | `docs/design/01_agent/README.md` through `docs/design/13_observability/README.md` | Dependent seam indexes do not yet link to the Overview requirements and invariants that they own. | `Change documentation state`: each owner seam adds exact trace links after approval. |

## Conflict dispositions

These dispositions replace conflicting or over-specific text from the
superseded Overview documents. They are recommendations until approval.

| Conflict or pressure point | Recommended disposition | Requirement or owner |
| --- | --- | --- |
| Plugin preparation occurs before route selection. | Change to source-Signal selection before preparation. | `OVR-REQ-013` through `OVR-REQ-015`; seams 04 and 05 |
| Current routing rejects multiple matches. | Select the first Router target by existing precedence. | `OVR-REQ-014`; seam 04 |
| Plugins see the complete Agent and share prepared input. | Add declared Agent views and isolated Plugin-owned inputs. | `OVR-REQ-021`; seams 01, 04, and 05 |
| Earlier text says nonpersistent restart resets to the initial Agent. | Remove that target. Keep last-commit runtime-checkpoint restore. | `OVR-REQ-044` and `OVR-REQ-045`; seams 08 through 10 |
| Earlier text says all runtime effects start after commit. | Limit the rule to runtime-owned Directive work. External executable I/O can occur before commit. | `OVR-REQ-027` through `OVR-REQ-030`; seam 06 |
| Earlier text names `%Jido.Plugin{}` as a configuration struct. | Remove the type claim. `Jido.Plugin` is a behavior. | `OVR-REQ-052`; seam 05 |
| Core has no stable Agent Ref. | Add Ref through a staged migration. | `OVR-REQ-011` and `OVR-REQ-012`; seams 03, 07, 09, and 10 |
| Core has no positive definition revision. | Add revision through a staged migration. Do not claim that a label pins loaded code. | `OVR-REQ-009` and `OVR-REQ-010`; seams 01, 02, 04, and 07 |
| Earlier proposals name Checkpoint, Commit, Record, Status, Turn Status, Plugin Context, Transition, Contribution, Runtime values, and Instance Config structs. | Keep the roles. Defer exact types, fields, serialization, and errors to their owners. | `OVR-REQ-052`; seam 12 and value owners |
| Earlier text can imply a new Result value. | Keep the tagged live result and the separate Turn Outcome. | Public/shared contract; seams 08, 12, and 13 |
| Plugin runtime Init lacks current state and version. | Add a coherent replacement input and keep the state-pull API during migration. | `OVR-REQ-048`; seams 05, 08, and 10 |
| Confirmed persistence errors can leave a writable Server active. | Remove write authority after every persistence write failure. | `OVR-REQ-039`; seams 07 and 08 |
| Persistent startup has no initial active record. | Add the record after provisional Plugin readiness and before Agent readiness. | `OVR-REQ-040`; seams 07, 08, and 10 |
| Durable delete removes revision history. | Use a compare-and-swap tombstone with explicit retention, purge, and reactivation rules. | `OVR-REQ-042`; seam 07 |
| Old proposals remove Builder and Codec. | Remove the removal proposal. Keep both APIs. | `OVR-REQ-008` and `OVR-REQ-063`; seams 01 and 02 |
| Old proposals remove public PID APIs immediately. | Keep PID APIs during a Ref-first migration. | `OVR-REQ-012` and `OVR-REQ-063`; seams 03, 08, 09, and 12 |
| The four Plugin facets do not exist. | Approve only the owner categories in this seam. Defer callbacks and checkpoint composition. | `OVR-REQ-005`; seam 05 with 01 and 07 |
| A Topology authoring owner exists but does not own the live target. | Keep authoring. Defer live authority and updates. | `OVR-REQ-060` and `OVR-REQ-061`; seam 11 |
| Plugin wrappers share the Agent Dynamic Supervisor. | Require separate logical roles only. Defer physical pool changes. | `OVR-REQ-047`; seams 09 and 10 |
| Legacy telemetry, tracing, and debug coexist with semantic events. | Keep all supported paths until semantic replacement coverage exists. | `OVR-REQ-054` through `OVR-REQ-059`, `OVR-REQ-063`; seam 13 |
| Per-Agent persistence override and instance persistence both exist. | Preserve both until seams 90, 07, and 09 decide compatibility. | `OVR-REQ-063`; seams 90, 07, and 09 |
| Future durable, cluster, and transport package names do not have complete APIs. | Keep only the package-boundary direction. Defer APIs until integration proof exists. | `OVR-REQ-062`; seams 90 and 99 |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
After the Overview intent and requirements are approved, `ce-plan` will create
the implementation tasks.

### Phase 0 — Approve the shared baseline

- Requirements: all `OVR-REQ` identifiers.
- Required outcome: one approved model, vocabulary, invariant set, and conflict
  disposition.
- Compatibility: no runtime change.
- Verification: document review against canonical evidence.
- Exit criteria: the user approves or changes each `OVR-DEC` item.

### Phase 1 — Lock package and public-contract policy

- Requirements: `OVR-REQ-001` through `OVR-REQ-005`, `OVR-REQ-052`,
  `OVR-REQ-053`, `OVR-REQ-062`, `OVR-REQ-063`, `OVR-REQ-065`, and
  `OVR-REQ-066`.
- Required outcome: approved package direction, extension categories, error
  ownership, value ownership, and compatibility rules.
- Owner gates: seam 90, then seam 12.
- Compatibility: current authoring, PID, persistence, and observation APIs stay
  available.
- Verification: public API inventory and compatible V3 package checks.
- Exit criteria: seams 90 and 12 can state one owner for every later public
  contract.

### Phase 2 — Align Agent, authoring, identity, and Turn

- Requirements: `OVR-REQ-006` through `OVR-REQ-023`.
- Required outcome: immutable Agent roles, normalized authoring, stable
  identity direction, definition revision, source-Signal routing, direct/live
  parity, and Plugin isolation boundaries.
- Owner gates: seams 01, 02, 03, and 04, in graph order.
- Compatibility: Builder, Codec, neutral definitions, custom routing, custom
  checkpoints, ID APIs, and PID handles remain.
- Verification: Agent, authoring, route, stable-reference, revision, and Turn
  acceptance tests.
- Exit criteria: the four owner alignments are approved, and target evidence is
  passing or explicitly deferred.

### Phase 3 — Align Plugin ownership

- Requirements: `OVR-REQ-005`, `OVR-REQ-019` through `OVR-REQ-023`,
  `OVR-REQ-031` through `OVR-REQ-034`, `OVR-REQ-047` through `OVR-REQ-049`.
- Required outcome: one ordered Plugin declaration with explicit owner
  categories, data authority, state ownership, and runtime replacement input.
- Owner gate: seam 05.
- Compatibility: compatibility delegates preserve supported callbacks and
  custom Agent checkpoint meaning.
- Verification: Plugin contract, isolation, Scheduler recovery, and runtime
  replacement tests.
- Exit criteria: seam 05 is approved and checkpoint interaction is explicit.

### Phase 4 — Align commit, effects, and durability

- Requirements: `OVR-REQ-024` through `OVR-REQ-043` and `OVR-REQ-064`.
- Required outcome: one commit boundary, honest external-I/O scope, recoverable
  capability pattern, safe write authority, initial record, restore, and
  tombstone lifecycle.
- Owner gates: seam 06, then seam 07.
- Compatibility: binary adapters and compare-and-swap stay. Record and delete
  changes need a versioned migration.
- Verification: commit, Directive, persistence-failure, portability, create,
  delete, purge, restart, and reactivation tests.
- Exit criteria: seams 06 and 07 are approved and each lifecycle state has an
  owner and passing evidence.

### Phase 5 — Align live ownership and runtime topology

- Requirements: `OVR-REQ-011`, `OVR-REQ-012`, `OVR-REQ-040`,
  `OVR-REQ-041`, `OVR-REQ-044` through `OVR-REQ-051`.
- Required outcome: approved Agent Server, Jido instance, Plugin runtime, and
  process-ownership contracts.
- Owner gates: seams 08, 09, and 10.
- Compatibility: Ref-first APIs are additive. PID APIs and runtime-checkpoint
  restore remain. Any pool change preserves restart behavior.
- Verification: public API, instance, supervisor, runtime lifecycle, owned
  child, readiness, and distributed-boundary tests.
- Exit criteria: restart sources, readiness, local resolution, and logical
  runtime roles are proved.

### Phase 6 — Align Topology control and observation

- Requirements: `OVR-REQ-054` through `OVR-REQ-061` and `OVR-REQ-063`.
- Required outcome: static local Topology remains supported, future live
  control stays bounded, semantic events become primary, and legacy migration
  has proof.
- Owner gates: seam 11, then seam 13.
- Compatibility: no current Topology or observation API is removed without a
  separate staged plan.
- Verification: Controller, authoring-host, telemetry, and observation tests.
- Exit criteria: live Topology work is approved or deferred, and any legacy
  removal has complete replacement evidence.

### Phase 7 — Close delivery

- Requirements: all approved Overview and dependent-seam requirements.
- Required outcome: one V3 release scope and migration order.
- Owner gate: seam 99.
- Compatibility: release notes list each additive, changed, deprecated, and
  deferred contract.
- Verification: full core quality checks, compatible V3 package tests, examples,
  and migration probes.
- Exit criteria: the delivery alignment is approved and required acceptance
  gates pass.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `OVR-REQ-001` through `OVR-REQ-005` | `lib/jido.ex:8-48`; `../jido_action/lib/jido_exec.ex:1-18`; `../jido_signal/lib/jido_signal/router.ex:1-16`; `mix.exs:351-360` | Seam-90 boundary inventory and compatible V3 compile and test result. | `Partial` |
| `OVR-REQ-006` through `OVR-REQ-008` | `lib/jido/agent.ex:2-10`; `test/jido/agent_test.exs:157-389`; `test/jido/agent/builder_test.exs:19-65`; `test/jido/agent/codec_test.exs:29-67` | Preserve every supported authoring form through the normalized target. | `Proven` for current behavior; target remains pending |
| `OVR-REQ-009` and `OVR-REQ-010` | `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:16-27` has one passing and one skipped case. | Revision field, all-authoring-form round trip, mismatch rejection, and old-checkpoint migration. | `Missing` |
| `OVR-REQ-011` and `OVR-REQ-012` | `lib/jido/agent_server.ex:295-309`; `lib/jido/persistence.ex:153-159`; `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:21-80` | Core Ref construction, serialization, Registry, persistence, delivery, node-move, and stale-location tests. | `Partial` |
| `OVR-REQ-013` through `OVR-REQ-015` | `../jido_signal/lib/jido_signal/router/index.ex:95-103`; `lib/jido/agent/command/runner.ex:64-90,178-193`; `test/examples/99_research/99_09_route_selection/route_selection_test.exs:23-37` | Direct and live first-match tests for exact, `*`, `**`, predicate, priority, declaration order, and route-changing Plugins. | `Conflict` |
| `OVR-REQ-016` through `OVR-REQ-018` | `lib/jido/agent/command/runner.ex:29-132`; `test/examples/99_research/99_09_route_selection/route_selection_test.exs:6-14` | Preserve parity after the route and Plugin-input changes. | `Proven` for current behavior |
| `OVR-REQ-019` through `OVR-REQ-023` | `lib/jido/plugin.ex:238-255,797-875`; `test/jido/plugin/contract_test.exs:490-670`; `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:22-34` | Declared observation, isolated input, deterministic merge, and direct/live parity. | `Partial` |
| `OVR-REQ-024` through `OVR-REQ-030` | `lib/jido/agent_server.ex:1493-1545,1639-1756`; `test/jido/agent_server/public_api_test.exs:87-181`; `test/jido/agent_server/directive_execution_test.exs:27-184` | Keep equal-state and paired pre-commit failure proof. Keep explicit executable-I/O limits. | `Proven` for current target wording |
| `OVR-REQ-031` through `OVR-REQ-034` | `lib/jido/plugin/scheduler.ex:30-48`; `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-212` | Preserve stable ID, retry, acknowledgement, unrelated-Turn, and restart proof. | `Proven` for Scheduler |
| `OVR-REQ-035` and `OVR-REQ-036` | `lib/jido/persistence/adapter.ex:1-46`; `test/jido/persistence_test.exs:422-503` | Run the adapter contract for every supported adapter and compatible V3 package set. | `Proven` for current adapter contract |
| `OVR-REQ-037` and `OVR-REQ-038` | `lib/jido/agent_server.ex:1493-1545`; `test/jido/persistence/indeterminate_write_test.exs:35-93` | Preserve for all write-result classes. | `Proven` |
| `OVR-REQ-039` | `test/jido/persistence/indeterminate_write_test.exs:35-93`; `test/jido/persistence_test.exs:305-347` | Conflict, confirmed error, exception, timeout, and indeterminate matrix with no later Turn before reload. | `Conflict` |
| `OVR-REQ-040` | `lib/jido/agent_server.ex:506-544,2887-2905` | Revision-zero active record, publication, and cleanup for readiness and write failures. | `Missing` |
| `OVR-REQ-041` | `lib/jido/agent_server.ex:2887-2905`; `test/jido/persistence_test.exs:359-394`; `test/jido/topology/controller_test.exs:251-285` | Preserve latest-record restore with the new record lifecycle. | `Proven` for current record |
| `OVR-REQ-042` | `lib/jido/persistence.ex:137-150`; `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:13-31` | Tombstone retention, purge, reactivation, stale-writer, and rollback tests. | `Missing` |
| `OVR-REQ-043` | `lib/jido/persistence.ex:285-315`; `test/jido/persistence/checkpoint_portability_test.exs:15-45` | Cross-boundary negative matrix for each approved durable value. | `Partial` |
| `OVR-REQ-044` and `OVR-REQ-045` | `lib/jido/agent_server/runtime_checkpoint.ex:8-50`; `test/jido/agent_server/runtime_lifecycle_test.exs:293-326` | Add explicit full-instance-stop proof that the nondurable checkpoint is gone. | `Partial` |
| `OVR-REQ-046` and `OVR-REQ-047` | `lib/jido/agent_server.ex:2-10`; `lib/jido.ex:346-370`; `lib/jido/agent_server/plugin_lifecycle.ex:110-198`; `test/jido/supervisor_test.exs:15-54` | If pools change, prove peer Agent behavior, Plugin isolation, and restart coupling. | `Proven` for logical roles |
| `OVR-REQ-048` | `test/jido/agent_server/runtime_lifecycle_test.exs:225-289`; `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:35-43` | State/version coherence for every replacement cause. | `Missing` |
| `OVR-REQ-049` | `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:14-32`; `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-212` | Preserve Signal reentry and mailbox serialization through Plugin migration. | `Proven` |
| `OVR-REQ-050` and `OVR-REQ-051` | `test/jido/agent_server/public_api_test.exs:333-459`; `lib/jido/agent_server.ex:1596-1637` | Preserve pre-commit cancellation and prove commit and Directive rejection. | `Partial` |
| `OVR-REQ-052` and `OVR-REQ-053` | `lib/jido/agent_server.ex:257-263,381-389,1878-1923`; `lib/jido/error.ex:1-17`; `test/jido/error/normalization_test.exs:8-321` | Seam-12 inventory for every public entry and protocol exception. | `Partial` |
| `OVR-REQ-054` through `OVR-REQ-059` | `lib/jido/telemetry.ex:8-30`; `test/jido/observe/agent_lifecycle_test.exs:10-302` | Add persistence, admission, Topology, and Agent Ref metadata cases. Keep legacy tests until retirement. | `Partial` |
| `OVR-REQ-060` and `OVR-REQ-061` | `lib/jido/topology/controller.ex:1-24,73-90`; `test/jido/topology/controller_test.exs:20-330`; `test/jido/topology/authoring_host_test.exs:79-272` | Add owner desired-state and live-target tests only if seam 11 approves those contracts. | `Proven` for static scope |
| `OVR-REQ-062` | `lib/jido.ex:8-48,346-370`; `mix.exs:351-360` | Seam-90 package contract and integration proof before any external package becomes required. | `Partial` |
| `OVR-REQ-063` | `test/jido/agent/builder_test.exs:19-65`; `test/jido/agent/codec_test.exs:29-67`; `test/jido/agent_server/public_api_test.exs:87-590`; `test/jido/persistence_test.exs:35-514`; `test/jido/observe/agent_lifecycle_test.exs:10-395` | Compatibility inventory, stated support period, and replacement proof before any deprecation. | `Partial` |
| `OVR-REQ-064` | `lib/jido/agent_server.ex:2887-2929`; `lib/jido/persistence.ex:119-135,285-315` | Preserve instance context in initial records, live commits, restore, tombstones, and reactivation. | `Partial` |
| `OVR-REQ-065` and `OVR-REQ-066` | `lib/jido/agent_server.ex:257-263,381-389`; `lib/jido/persistence.ex:59-99`; `test/jido/persistence_test.exs:79-94` | Complete seam-12 protocol-exception and option-validation inventory. | `Partial` |

## Migration and compatibility effects

No deprecation or removal is approved in this seam.

| Area | Compatibility effect and migration gate |
| --- | --- |
| Route order | First-match selection changes current multiple-match errors. Route-changing Plugin behavior needs a stated transition and direct/live acceptance proof. |
| Plugin input | Declared views and isolated prepared input change callback authority. Keep declaration order and supply compatibility delegates until Plugin migrations are proved. |
| Agent Ref | Add Ref-first APIs beside current ID and PID APIs. Do not remove current handles in V3 without a separate deprecation decision. |
| Definition revision | Preserve revision through DSL, direct data, Builder, Codec, checkpoints, and restore. Define behavior for old checkpoints before enforcement. |
| Custom checkpoints | Keep complete Agent `checkpoint/2` and `restore/2`. A Persistence facet cannot silently override their meaning. |
| Durable records | Version any new active and tombstone record shape. Define mixed-version read, write, purge, reactivation, and rollback rules before the first new-format write. |
| Write errors | Removing write authority after confirmed failures changes current error-policy behavior. Define stop or terminal non-writing behavior and automatic-restart reload rules. |
| Persistence adapters | Keep the binary adapter and atomic compare-and-swap contract. New lifecycle meaning stays above the adapter. |
| Plugin runtime Init | Add coherent state and version input. Keep the current public state-pull recovery path during migration. |
| Public values and errors | Add values and normalized errors only after owner, purpose, serialization, protocol exceptions, and caller migration are clear. |
| Topology | Keep static local activation and repair. Do not require live updates for V3. |
| Observation | Keep semantic events, legacy `:agent_server` telemetry, `Jido.Observe`, tracing, and debug until seam 13 proves replacement coverage. |
| Package versions | Test a declared compatible V3 pair. Do not use uncommitted sibling `jido_signal` behavior as proof for the Hex dependency. |

Release rollback must not cause an older runtime to ignore a tombstone or
misread a new identity or definition revision. The owner seams must define the
mixed-version gate before data-format changes. Supported APIs remain available
when a safe rollback requires them.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `OVR-BLK-001` | `Blocker` | 00 Overview | No `OVR-DEC` item is approved. Dependent seams cannot use target requirements as approved contracts. | User approval or changed decisions. |
| `OVR-BLK-002` | `Assumption` | 90 Package boundaries | Jido remains the local coordination layer above public `jido_action` and `jido_signal` contracts. | Confirm in seam 90. |
| `OVR-BLK-003` | `Blocker` | 04 Turn evaluation and `jido_action` | A definition revision does not by itself pin Action or Flow BEAM code for a complete Turn. | Decide executable code-revision scope and prove it at the execution boundary. |
| `OVR-BLK-004` | `Assumption` | 90 and Delivery | The declared Hex `jido_signal` V3 version has the Router precedence used by Jido. | Compile and test the declared compatible package set. |
| `OVR-BLK-005` | `Blocker` | 05 Plugins, 01 Agent, 07 Persistence | The proposed Persistence facet has no approved composition with complete custom Agent checkpoint callbacks. | Define explicit composition or defer the facet. |
| `OVR-BLK-006` | `Blocker` | 07 Persistence and 08 Agent Server | Initial records, write-authority loss, and tombstones lack final failure, retention, purge, reactivation, and restart rules. | Approve the durability scope, then define these rules in owner seams. |
| `OVR-BLK-007` | `Assumption` | 12 Errors and contracts | Maps, tuples, atoms, and OTP values can remain documented protocol exceptions. | Complete the seam-12 inventory and migration rules. |
| `OVR-BLK-008` | `Assumption` | 09 Jido instance and 10 Runtime topology | Plugin runtimes and Agent Servers need separate logical roles, but not necessarily separate Dynamic Supervisors. | Decide physical placement only after restart and readiness proof. |
| `OVR-BLK-009` | `Assumption` | 11 Topology control plane | Static local Topology is sufficient for the V3 release boundary. | Approve or change `OVR-DEC-009`. |

## Completion criteria

- [ ] The user has approved or changed each `OVR-DEC` item.
- [ ] Every approved `OVR-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains in the acceptance matrix.
- [ ] Compatibility and mixed-version rules are complete for each changed
  public or durable contract.
- [ ] Owner seams contain the detailed contracts assigned to them and link to
  the applicable `OVR-INV` and `OVR-REQ` identifiers.
- [ ] Compatible V3 `jido`, `jido_action`, and `jido_signal` versions compile
  and pass their required cross-package tests.
- [ ] Seam 99 records all additive, changed, deprecated, and deferred release
  items.
- [ ] After approval, `ce-plan` creates formal implementation tasks. This
  alignment document remains a high-level sequence only.
