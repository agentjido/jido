# Example capability coverage

This register maps public capabilities to one canonical learning example when
one exists. The owner column names the package that owns the contract. A Jido
example can integrate a capability that is owned by another package.

The stable folder count is an inventory for navigation. It is not a coverage
score. Combined application fixtures, ecosystem integrations, guides, and core
tests are valid evidence, but they do not each represent a new Jido capability.

## Status values

- **Focused example**: one stable lesson and behavior test teach the contract.
- **Combined example**: an application fixture combines contracts already
  taught elsewhere.
- **Guide-only**: the owner package documents the contract without a stable
  example.
- **Core-test-only**: regression tests prove details that would make a poor
  learning example.
- **Planned**: no accepted evidence exists yet.
- **Out of scope**: the repository does not claim the capability.

## Basic Agent contracts

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Agent definition, state, and one route | `jido` | Focused example | [Source](01_basic/01_01_minimal_agent/minimal_agent.ex), [test](../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs) |
| Typed command input and validation | `jido` | Focused example | [Source](01_basic/01_02_typed_command_agent/typed_command_agent.ex), [test](../test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs) |
| Plugin-owned Agent state | `jido` | Focused example | [Source](01_basic/01_03_plugin_state_agent/plugin_state_agent.ex), [test](../test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs) |
| Typed post-commit Directive dispatch | `jido` | Focused example | [Source](01_basic/01_04_directive_agent/directive_agent.ex), [test](../test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs) |
| Application supervision and runtime replacement | `jido` | Focused example | [Source](01_basic/01_05_otp_supervision/application.ex), [test](../test/examples/01_basic/01_05_otp_supervision/example_test.exs) |
| Route specificity and priority | `jido` | Focused example | [Source](01_basic/01_06_route_selection/route_selection.ex), [test](../test/examples/01_basic/01_06_route_selection/route_selection_test.exs) |
| Data-defined Agent and trusted Codec | `jido` | Focused example | [Source](01_basic/01_07_data_defined_agent/data_defined_agent.ex), [test](../test/examples/01_basic/01_07_data_defined_agent/data_defined_agent_test.exs) |
| Custom Signal selection and explicit Turn construction | `jido` | Focused example | [Source](01_basic/01_08_custom_signal_selection/custom_signal_selection.ex), [test](../test/examples/01_basic/01_08_custom_signal_selection/custom_signal_selection_test.exs) |
| Agent authoring extension lowering | `jido` | Focused example | [Source](01_basic/01_09_agent_extension/agent_extension.ex), [test](../test/examples/01_basic/01_09_agent_extension/agent_extension_test.exs) |

## Flow integration contracts

`jido_action` owns Actions, Instructions, Flows, execution, and Flow codecs.
The examples below stay in this repository because each lesson proves a
distinct Agent route or commit integration contract.

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Sequential Flow in an Agent route | `jido_action` | Focused example | [Source](02_workflow/02_01_sequential_flow/sequential_flow.ex), [test](../test/examples/02_workflow/02_01_sequential_flow/sequential_flow_test.exs) |
| Synchronous I/O steps through caller context | `jido_action` | Focused example | [Source](02_workflow/02_02_effectful_steps/effectful_steps.ex), [test](../test/examples/02_workflow/02_02_effectful_steps/effectful_steps_test.exs) |
| Conditional route Flow | `jido_action` | Focused example | [Source](02_workflow/02_03_conditional_routes/conditional_routes.ex), [test](../test/examples/02_workflow/02_03_conditional_routes/conditional_routes_test.exs) |
| Parallel join in one Agent Turn | `jido_action` | Focused example | [Source](02_workflow/02_04_parallel_join/parallel_join.ex), [test](../test/examples/02_workflow/02_04_parallel_join/parallel_join_test.exs) |
| Ordered batch and reduction | `jido_action` | Focused example | [Source](02_workflow/02_05_ordered_batch/ordered_batch.ex), [test](../test/examples/02_workflow/02_05_ordered_batch/ordered_batch_test.exs) |
| Bounded iteration and replacement-state validation | `jido_action` | Focused example | [Source](02_workflow/02_06_bounded_iteration/bounded_iteration.ex), [test](../test/examples/02_workflow/02_06_bounded_iteration/bounded_iteration_test.exs) |
| Nested Flow result and context boundaries | `jido_action` | Focused example | [Source](02_workflow/02_07_nested_flow/nested_flow.ex), [test](../test/examples/02_workflow/02_07_nested_flow/nested_flow_test.exs) |
| Executable continuation in an Agent Turn | `jido_action` | Focused example | [Source](02_workflow/02_08_executable_continuation/executable_continuation.ex), [test](../test/examples/02_workflow/02_08_executable_continuation/executable_continuation_test.exs) |
| Multi-step Directive collection and post-commit dispatch | `jido_action` | Focused example | [Source](02_workflow/02_09_flow_directives/flow_directives.ex), [test](../test/examples/02_workflow/02_09_flow_directives/flow_directives_test.exs) |

## Runtime contracts

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Scheduled Signals | `jido` | Focused example | [Source](04_runtime/04_01_scheduled_signals/scheduled_counter.ex), [test](../test/examples/04_runtime/04_01_scheduled_signals/scheduled_counter_test.exs) |
| Keyed replaceable timers | `jido` | Focused example | [Source](04_runtime/04_02_keyed_timers/burst_buncher.ex), [test](../test/examples/04_runtime/04_02_keyed_timers/burst_buncher_test.exs) |
| Agent-owned Bus delivery and recovery | `jido` | Focused example | [Source](04_runtime/04_03_bus_delivery/bus_delivery.ex), [test](../test/examples/04_runtime/04_03_bus_delivery/bus_delivery_test.exs) |
| Managed post-commit jobs | `jido` | Focused example | [Source](04_runtime/04_04_managed_jobs/managed_jobs.ex), [test](../test/examples/04_runtime/04_04_managed_jobs/managed_jobs_test.exs) |
| Public runtime inspection and bounded debug events | `jido` | Focused example | [Source](04_runtime/04_05_runtime_inspection/agent_live_debugger.ex), [test](../test/examples/04_runtime/04_05_runtime_inspection/agent_live_debugger_test.exs) |
| Semantic Agent observation | `jido` | Focused example | [Source](04_runtime/04_07_agent_observation/turn_observation.ex), [test](../test/examples/04_runtime/04_07_agent_observation/agent_observation_test.exs) |
| Causal trace across parent and child work | `jido` | Focused example | [Source](04_runtime/04_08_causal_trace/causal_trace.ex), [test](../test/examples/04_runtime/04_08_causal_trace/causal_trace_test.exs) |
| Pending managed-job recovery | `jido` | Focused example | [Source](04_runtime/04_10_pending_job_recovery/pending_job_recovery.ex), [test](../test/examples/04_runtime/04_10_pending_job_recovery/pending_job_recovery_test.exs) |
| Durable scheduling occurrence protocol | `jido` | Focused example | [Source](04_runtime/04_11_durable_scheduling/scheduled_occurrence_recovery.ex), [test](../test/examples/04_runtime/04_11_durable_scheduling/durable_scheduling_test.exs) |
| Stable Agent Ref and partition identity | `jido` | Focused example | [Source](04_runtime/04_12_stable_reference/stable_reference.ex), [test](../test/examples/04_runtime/04_12_stable_reference/stable_reference_test.exs) |
| Serialized Turn upgrade | `jido` | Focused example | [Source](04_runtime/04_13_turn_upgrade/turn_upgrade.ex), [test](../test/examples/04_runtime/04_13_turn_upgrade/turn_upgrade_test.exs) |
| Validated state migration | `jido` | Focused example | [Source](04_runtime/04_14_state_migration/state_migration.ex), [test](../test/examples/04_runtime/04_14_state_migration/state_migration_test.exs) |
| Call, cast, and asynchronous request modes | `jido` | Focused example | [Source](04_runtime/04_15_request_modes/request_modes.ex), [test](../test/examples/04_runtime/04_15_request_modes/request_modes_test.exs) |
| Active Turn inspection and cancellation | `jido` | Focused example | [Source](04_runtime/04_16_turn_control/turn_control.ex), [test](../test/examples/04_runtime/04_16_turn_control/turn_control_test.exs) |
| Failure policy and public Turn Outcome | `jido` | Focused example | [Source](04_runtime/04_17_failure_outcome/failure_outcome.ex), [test](../test/examples/04_runtime/04_17_failure_outcome/failure_outcome_test.exs) |
| Heartbeat Plugin lifecycle | `jido` | Focused example | [Source](04_runtime/04_18_heartbeat/heartbeat.ex), [test](../test/examples/04_runtime/04_18_heartbeat/heartbeat_test.exs) |

## Multi-agent contracts

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Direct child lifecycle | `jido` | Focused example | [Source](05_multi_agent/05_01_child_lifecycle/child_lifecycle.ex), [test](../test/examples/05_multi_agent/05_01_child_lifecycle/child_lifecycle_test.exs) |
| Correlated child request and stale reply rejection | `jido` | Focused example | [Source](05_multi_agent/05_02_correlated_requests/correlated_requests.ex), [test](../test/examples/05_multi_agent/05_02_correlated_requests/correlated_requests_test.exs) |
| Owned Agent hierarchy | `jido` | Focused example | [Source](05_multi_agent/05_03_agent_hierarchy/agent_hierarchy.ex), [test](../test/examples/05_multi_agent/05_03_agent_hierarchy/agent_hierarchy_test.exs) |
| Exact remote child placement | `jido` | Focused example | [Source](05_multi_agent/05_04_remote_child/remote_child.ex), [test](../test/examples/05_multi_agent/05_04_remote_child/remote_child_test.exs) |
| Remote exit versus connection uncertainty | `jido` | Focused example | [Source](05_multi_agent/05_05_remote_lifecycle/remote_lifecycle.ex), [test](../test/examples/05_multi_agent/05_05_remote_lifecycle/remote_lifecycle_test.exs) |
| Orphan policy and child adoption | `jido` | Focused example | [Source](05_multi_agent/05_06_orphan_adoption/orphan_adoption.ex), [test](../test/examples/05_multi_agent/05_06_orphan_adoption/orphan_adoption_test.exs) |

## Topology contracts

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Independent Agents and repair | `jido` | Focused example | [Source](07_topology/07_01_independent/independent.ex), [test](../test/examples/07_topology/07_01_independent/independent_test.exs) |
| Declared ownership hierarchy | `jido` | Focused example | [Source](07_topology/07_02_hierarchy/hierarchy.ex), [test](../test/examples/07_topology/07_02_hierarchy/hierarchy_test.exs) |
| Bounded Bus swarm in DSL, data, and Codec forms | `jido` | Focused example | [Source](07_topology/07_03_bus_swarm/swarm.ex), [test](../test/examples/07_topology/07_03_bus_swarm/bus_swarm_test.exs) |
| Keyed group identity | `jido` | Focused example | [Source](07_topology/07_04_keyed_accounts/accounts.ex), [test](../test/examples/07_topology/07_04_keyed_accounts/keyed_accounts_test.exs) |
| Topology composition, imports, bindings, and exports | `jido` | Focused example | [Source](07_topology/07_05_composed_system/composed_system.ex), [test](../test/examples/07_topology/07_05_composed_system/composed_system_test.exs) |
| Plugin-contributed static wiring | `jido` | Focused example | [Source](07_topology/07_06_plugin_contribution/plugin_contribution.ex), [test](../test/examples/07_topology/07_06_plugin_contribution/plugin_contribution_test.exs) |
| Lifecycle Signals and degraded repair | `jido` | Focused example | [Source](07_topology/07_07_lifecycle_signals/lifecycle_signals.ex), [test](../test/examples/07_topology/07_07_lifecycle_signals/lifecycle_signals_test.exs) |
| Static and policy-selected exact placement | `jido` | Focused example | [Source](07_topology/07_08_placement_policy/placement_policy.ex), [test](../test/examples/07_topology/07_08_placement_policy/placement_policy_test.exs) |
| Additive live target update | `jido` | Focused example | [Source](07_topology/07_09_additive_update/additive_update.ex), [test](../test/examples/07_topology/07_09_additive_update/additive_update_test.exs) |
| Topology authoring extension lowering | `jido` | Focused example | [Source](07_topology/07_10_topology_extension/topology_extension.ex), [test](../test/examples/07_topology/07_10_topology_extension/topology_extension_test.exs) |

## Application and Plugin contracts

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Committed audit state | `jido` | Focused example | [Source](08_applications/08_01_audit/audit.ex), [test](../test/examples/08_applications/08_01_audit/audit_test.exs) |
| Subscription resource rebuilt from committed state | `jido` | Focused example | [Source](08_applications/08_02_subscription/subscription.ex), [test](../test/examples/08_applications/08_02_subscription/subscription_test.exs) |
| Managed sensor input and duplicate rejection | `jido` | Focused example | [Source](08_applications/08_03_inbox/inbox.ex), [test](../test/examples/08_applications/08_03_inbox/inbox_test.exs) |
| Multi-Turn approval correlation and idempotency | `jido` | Focused example | [Source](08_applications/08_04_approval_workflow/approval_workflow.ex), [test](../test/examples/08_applications/08_04_approval_workflow/approval_workflow_test.exs) |
| Bounded scheduled purpose loop | `jido` | Focused example | [Source](08_applications/08_06_purpose_loop/purpose_loop.ex), [test](../test/examples/08_applications/08_06_purpose_loop/purpose_loop_test.exs) |
| Fixed group coordination policy | `jido` | Combined example | [Source](08_applications/08_07_fixed_group/fixed_group.ex), [test](../test/examples/08_applications/08_07_fixed_group/fixed_group_test.exs) |
| Elastic scale, recovery, and drain policy | `jido` | Combined example | [Source](08_applications/08_08_elastic_group/elastic_group.ex), [test](../test/examples/08_applications/08_08_elastic_group/elastic_group_test.exs) |
| Pure prepared Plugin input | `jido` | Focused example | [Source](09_plugins/09_01_prepared_input/prepared_input.ex), [test](../test/examples/09_plugins/09_01_prepared_input/prepared_input_test.exs) |
| Live Plugin admission input | `jido` | Focused example | [Source](09_plugins/09_02_runtime_admission/runtime_admission.ex), [test](../test/examples/09_plugins/09_02_runtime_admission/runtime_admission_test.exs) |
| Signed identity and runtime-generation replay protection | `jido` | Focused example | [Source](09_plugins/09_03_identity/identity.ex), [test](../test/examples/09_plugins/09_03_identity/identity_test.exs) |
| Encrypted Signal preparation | `jido` | Focused example | [Source](09_plugins/09_04_secure_signal/secure_signal.ex), [test](../test/examples/09_plugins/09_04_secure_signal/secure_signal_test.exs) |
| Independent Plugin input composition | `jido` | Focused example | [Source](09_plugins/09_05_composition/composition.ex), [test](../test/examples/09_plugins/09_05_composition/composition_test.exs) |
| Plugin-owned state reduction | `jido` | Focused example | [Source](09_plugins/09_06_state_middleware/state_middleware.ex), [test](../test/examples/09_plugins/09_06_state_middleware/state_middleware_test.exs) |
| Live projection after commit | `jido` | Focused example | [Source](09_plugins/09_08_commit_projection/commit_projection.ex), [test](../test/examples/09_plugins/09_08_commit_projection/commit_projection_test.exs) |

## Persistence contracts

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Revision-zero activation, commits, restore, and identity | `jido` | Focused example | [Source](10_persistence/10_01_persistent_agent/persistent_agent.ex), [tests](../test/examples/10_persistence/10_01_persistent_agent/) |
| Hibernate, thaw, Ref lifetime controls, and idle hibernation | `jido` | Focused example | [Source](10_persistence/10_02_hibernate_and_thaw/hibernate_and_thaw.ex), [test](../test/examples/10_persistence/10_02_hibernate_and_thaw/hibernate_and_thaw_test.exs) |
| Checkpoint portability validation | `jido` | Focused example | [Source](10_persistence/10_03_portable_checkpoint/checkpoint_portability_probe.ex), [test](../test/examples/10_persistence/10_03_portable_checkpoint/checkpoint_portability_test.exs) |
| Plugin-owned state conversion and validation | `jido` | Focused example | [Source](10_persistence/10_04_plugin_state_conversion/persisted_state.ex), [test](../test/examples/10_persistence/10_04_plugin_state_conversion/persisted_state_test.exs) |
| Exact-byte CAS, deletion, and tombstone fencing | `jido` | Focused example | [Source](10_persistence/10_05_durable_delete/durable_delete.ex), [test](../test/examples/10_persistence/10_05_durable_delete/durable_delete_test.exs) |
| Indeterminate write isolation and cleanup | `jido` | Focused example | [Source](10_persistence/10_06_indeterminate_write/indeterminate_write_probe.ex), [test](../test/examples/10_persistence/10_06_indeterminate_write/indeterminate_write_test.exs) |
| Recoverable external delivery intent | `jido` | Focused example | [Source](10_persistence/10_07_recoverable_delivery/recoverable_delivery.ex), [test](../test/examples/10_persistence/10_07_recoverable_delivery/recoverable_delivery_test.exs) |
| Definition revision compatibility | `jido` | Focused example | [Source](10_persistence/10_08_definition_revision/definition_revision.ex), [test](../test/examples/10_persistence/10_08_definition_revision/definition_revision_test.exs) |

All persistence examples use deterministic local adapters. Shared external
adapter checks remain optional service tests.

## Ecosystem and combined suites

| Capability | Owner | Status | Canonical evidence |
| --- | --- | --- | --- |
| Model response, history, tool use, bounded tool loops, and output repair | `jido_ai` | Combined example | [Jido ecosystem integration sources](03_llm/README.md), [tests](../test/examples/03_llm/README.md) |
| Conversation, multi-Agent factory, department plan, and Flow factory applications | `jido` | Combined example | [Optional Factory suite](06_factory/README.md), [tests](../test/examples/06_factory/README.md) |
| Distributed exclusive authority and fencing | `jido` | Out of scope | [Research evidence](99_research/99_02_distributed_authority/README.md), [peer test](../test/examples/99_research/99_02_distributed_authority/fenced_inventory_test.exs) |

The LLM group is an ecosystem integration suite, not Jido public-feature
coverage. `jido_ai` owns its model and tool orchestration contracts and has its
own example catalog. The Factory group is an optional combined application
suite. Its four fixtures do not count as four new Jido capabilities. Its best
future home is `examples/jido_lab`, where application demonstrations can span
packages without changing core ownership.

## Contracts owned by other packages

| Capability | Owner | Status | Current evidence |
| --- | --- | --- | --- |
| Action, Instruction, and Action output mechanics | `jido_action` | Core-test-only | [Owner-package example test](../../jido_action/test/examples/action_effects_test.exs) |
| Flow authoring extensions | `jido_action` | Guide-only | [Owner-package guide](../../jido_action/guides/flow-modules.md) |
| Flow Codec diagnosis | `jido_action` | Guide-only | [Owner-package storage guide](../../jido_action/guides/flow-storage.md) |
| Step-wise execution | `jido_action` | Guide-only | [Owner-package debugging guide](../../jido_action/guides/debugging-flows.md) |
| Signal envelope, serialization, routing, dispatch, and local Bus | `jido_signal` | Guide-only | [Owner-package public contracts](../../jido_signal/guides/public-contracts.md) |

Detailed Flow execution stays in `jido_action`. This repository keeps only the
Flow examples that prove a distinct Agent integration or commit boundary.

## Placement decisions

- The former runtime state-recovery lesson moved from `04_06` to `10_01`.
- Recoverable delivery moved from `04_09` to `10_07`.
- `04_10` and `04_11` stay in Runtime because managed-job and Scheduler
  recovery are their main lessons. Their persistence is supporting evidence.
- Stable Ref, Turn upgrade, and state migration stay in Runtime because
  identity and upgrade behavior are their main lessons.
- Persisted Plugin state moved from `09_07` to `10_04`. The Plugin index links
  to the persistence lesson.
- Fixed and elastic groups stay as combined application policy examples. They
  are not separate core capacity or autoscaling claims.
- Distributed authority stays in Research until Jido has a supported fencing
  and exclusive-ownership contract.

## Deliberate non-goals

- Function overloads, aliases, error constructors, and utility helpers do not
  each need a stable example.
- Directives appear inside workflows that give them meaning. There is no
  one-example-per-Directive target.
- Large malformed-input matrices, bounds, and scheduler interleavings stay in
  core tests.
- OpenTelemetry exporter setup and deployment configuration stay in guides.
- Provider-specific persistence checks stay optional.
- Application autoscaling and distributed ownership policy are not Jido core
  contracts.
