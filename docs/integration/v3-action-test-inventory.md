# V3 Action integration test inventory

Date: 2026-10-14. Repository: `jido`. Branch: `release/v3`.

The baseline below records the first inventory run. The historical sections
retain the evidence before the AgentServer change.

## Started execution integration

Checkpoint: `4e9112d`. AgentServer now uses one owned local started execution
per Turn. See the [implementation and simplification check](started-execution.md).

The core and property suite passes: 1,488 passed, 51 excluded. The 269
missing-async failures and 27 live follow-up failures are resolved. No tests
were skipped or disabled for this integration.

The local Agent system suite passes all 63 tests across ETS, file, and Ecto
adapters. Action passes all 1,059 tests. Runic passes 2,027 tests with its 13
existing skips. All nine authoring JSON export Dialyzer diagnostics are fixed.
The generator now emits a return spec that matches static schema support.

The first full package run after AgentServer integration passed 2,430 of 2,437
tests, with two existing skips and 161 normal exclusions. Its seven failures
are now fixed:

| Example | Original failures | Fix |
| --- | ---: | --- |
| `02_08_executable_continuation` | 2 | Dispatch selects an Action or a Flow with native bounded Iterate. |
| `03_04_tool_loop` | 4 | Dispatch selects a ToolRound Flow; normal tool output feeds ReasonFlow under the existing step budget. |
| `06_04_flow_factory` | 1 | Choice selects roles before Map starts quality and security work at the same causal depth. |

All 23 focused tests for these three examples pass. The Factory overlap
assertion is unchanged. Runic retains its documented stable order. No scheduler
change or graph padding was required.

The Turn deadline test now uses a barrier and an expired absolute deadline.
It exposed a result-ordering race: a late admission error could reach the caller
before the timer message. AgentServer now checks the deadline before it accepts
any admission result. All seven context tests pass, including timeout recovery.

The first extended full run also exposed a private-state test race. Work can
start before the Server receives the lifecycle task's start result. Tests that
read the native handle now wait for `:running`; the public responsiveness test
accepts `:starting` and `:running`. The 42 focused runtime tests pass, including
the property and fuzz variants.

The final full run (`mix test.all --include fuzz --cover --warnings-as-errors`)
passes all 2,451 tests, with two existing skips and 147 service exclusions.
Core coverage is 93.0%. `mix quality` passes, including Dialyzer with no errors.
Action's full suite with the pinned Runic fork passes all 1,059 tests, with
95.06% coverage. See the implementation report for the commands, extra check
failures, package limits, and one unreproduced Registry failure.

Input and output error assertions in the other Flow examples now use the
current structured Action errors and pass.

The first broad run also found an expired-call queue metric that counted its
own expired entry. Admission now removes that entry before it emits rejection
telemetry. All three adapter cases pass. A peer startup error from that run
did not recur in its focused run or the final serial full run.

## Independent patches before the checkpoint

- Removed `max_continuations` from the selection test. Direct and live selection checks are now separate tests. The direct check passes; the live check remains enabled and reaches the missing async API.
- Fixed improper-list wrapping, unwrapping, and local identity detection in `jido_action/lib/jido_exec/fact.ex`. Four regression tests cover root and nested values, native Fact propagation, and public `Jido.Exec.run/4` input/output. The original core local-value test now passes.
- AgentServer implementation is unchanged. No tests were skipped or disabled.

### Verification after fixes

| Check | Result |
| --- | --- |
| Action focused Fact, node, and portability tests | 37 passed |
| Action final Fact regression file | 7 passed |
| Action default suite with strict compilation and coverage | 923 passed, 132 excluded; 95.11% coverage |
| Action complete suite, including authoring, property, fuzz, system, and load | 1,055 passed |
| Action format, strict compile, Credo, Dialyzer, and docs | Passed |
| Core focused direct selection, local state, Flow, Codec, and Registry checks | 18 passed |
| Core `mix test test/jido --seed 0` | 1,139 passed, 296 failed, 37 excluded |

At the checkpoint, core failures contained 269 explicit missing-async failures and 27 live follow-up failures. The removed-option and direct improper-list failure groups were resolved. The added direct selection test increased the executed test count by one; the original mixed test was retained as a live check.

The next step at that point was the AgentServer lifecycle change. It is now
implemented and verified as described above.

## Baseline command and scope

```sh
mix test test/jido --seed 0
```

Result: 1,137 passed, 297 failed, 37 excluded. The run took 67.1 seconds.

The command used the normal test exclusions from `test/test_helper.exs`. No new exclusions or skips were added. This run did not select the property, peer, example, authoring, benchmark, or system suites.

## Baseline failure groups

| Group | Failures | Evidence | Next action |
| --- | ---: | --- | --- |
| AgentServer execution | 268 | Failure output explicitly contains the removed `Jido.Exec.run_async/4` call. | Keep as one blocked group until the execution adapter changes. |
| Live execution follow-up | 27 | Missing messages, unchanged state, or error metadata assertions in live tests. | Likely effects of the execution failure. Rerun after the adapter change before changing assertions. |
| Removed execution option | 1 | Direct `Agent.cmd/3` rejects `max_continuations`. | Small test migration. The same test also calls AgentServer, so separate direct assertions before verification. |
| Direct local values | 1 | Direct `Agent.cmd/3` fails for an improper list. | Investigate and fix in `jido_action`; preserve the local-value contract. |

## Patch order from baseline

1. Completed: update `test/jido/agent/selection_test.exs:251` to stop passing `max_continuations: 0` for ordinary target selection. Keep the Action/Flow selection assertions. Split direct and live checks so the direct contract can be verified before AgentServer changes.
2. Completed: fix improper-list handling in the Action execution boundary. `Jido.Exec.Fact` uses `Enum.map/2` in its list wrap and unwrap paths, and `Enum.any?/2` in its local-value check. These paths assume proper lists. Add a focused regression in `jido_action`, then rerun `test/jido/agent/portable_state_test.exs:100` from core.
3. Change AgentServer execution, completion, cancellation, and shutdown cleanup as one patch. Then rerun the two live failure groups.

The improper-list issue is a lower-package change. Keep its edit, checks, and any commit scoped to `jido_action`.

## Independent value probe

A direct `Agent.cmd/3` probe used a `Zoi.any()` payload and an Action that returns its input. PID, reference, anonymous function, and non-byte-aligned bitstring payloads passed. `[1 | :tail]` failed with `FunctionClauseError` in `Enum.map/2`. This reproduces without AgentServer.

The existing core test also covers a port. The separate probe did not repeat that case.

## Baseline AgentServer failures by file

| File | Failures with explicit async error |
| --- | ---: |
| `test/jido/agent/authoring_test.exs` | 4 |
| `test/jido/agent/candidate_completeness_test.exs` | 2 |
| `test/jido/agent/flow_effects_test.exs` | 2 |
| `test/jido/agent/flow_expression_test.exs` | 1 |
| `test/jido/agent/replacement_test.exs` | 1 |
| `test/jido/agent/schema_test.exs` | 4 |
| `test/jido/agent/selection_test.exs` | 4 |
| `test/jido/agent/state_boundary_test.exs` | 2 |
| `test/jido/agent/state_intersection_test.exs` | 1 |
| `test/jido/agent/stateless_directive_test.exs` | 2 |
| `test/jido/agent/turn_evaluation_test.exs` | 2 |
| `test/jido/agent_server/after_commit_test.exs` | 19 |
| `test/jido/agent_server/child_lifecycle_test.exs` | 14 |
| `test/jido/agent_server/child_operation_task_test.exs` | 4 |
| `test/jido/agent_server/commit_boundary_test.exs` | 5 |
| `test/jido/agent_server/context_test.exs` | 6 |
| `test/jido/agent_server/directive_execution_test.exs` | 14 |
| `test/jido/agent_server/effect_recovery_test.exs` | 9 |
| `test/jido/agent_server/emit_dispatch_test.exs` | 3 |
| `test/jido/agent_server/execution_context_test.exs` | 1 |
| `test/jido/agent_server/failure_contract_test.exs` | 4 |
| `test/jido/agent_server/pending_job_recovery_test.exs` | 4 |
| `test/jido/agent_server/public_api_test.exs` | 14 |
| `test/jido/agent_server/runtime_boundary_test.exs` | 3 |
| `test/jido/agent_server/runtime_checkpoint_test.exs` | 3 |
| `test/jido/agent_server/runtime_lifecycle_test.exs` | 5 |
| `test/jido/agent_server/runtime_observability_test.exs` | 5 |
| `test/jido/agent_server/supervision_test.exs` | 4 |
| `test/jido/agent_server/upgrade_test.exs` | 2 |
| `test/jido/instance_ref_test.exs` | 4 |
| `test/jido/persistence/conformance/local_test.exs` | 16 |
| `test/jido/persistence/indeterminate_write_test.exs` | 4 |
| `test/jido/persistence/live_state_test.exs` | 3 |
| `test/jido/persistence_test.exs` | 4 |
| `test/jido/plugin/audit_test.exs` | 3 |
| `test/jido/plugin/authoring_runtime_test.exs` | 8 |
| `test/jido/plugin/preparation_test.exs` | 1 |
| `test/jido/plugin/scheduler/live_runtime_test.exs` | 4 |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs` | 7 |
| `test/jido/plugin/scheduler/occurrence_runtime_test.exs` | 4 |
| `test/jido/plugin/sensor_manager_test.exs` | 3 |
| `test/jido/plugin/state_runtime_test.exs` | 1 |
| `test/jido/telemetry/agent_lifecycle_test.exs` | 8 |
| `test/jido/telemetry/open_telemetry_test.exs` | 1 |
| `test/jido/topology/authoring_host_test.exs` | 1 |
| `test/jido/topology/child_runtime_test.exs` | 4 |
| `test/jido/topology/controller/composition_runtime_test.exs` | 3 |
| `test/jido/topology/controller/resource_race_test.exs` | 1 |
| `test/jido/topology/controller/supervision_test.exs` | 4 |
| `test/jido/topology/controller_boundary_test.exs` | 4 |
| `test/jido/topology/controller_test.exs` | 3 |
| `test/jido/topology/controller_update_test.exs` | 1 |
| `test/jido/topology/runtime_checkpoint_test.exs` | 11 |
| `test/jido/topology/runtime_hibernate_test.exs` | 5 |
| `test/jido/topology/runtime_ownership_test.exs` | 1 |
| `test/jido/topology/runtime_test.exs` | 8 |
| `test/jido/tracing/causal_trace_test.exs` | 7 |

## Live failures to recheck after execution changes

These are provisional groups. Their output does not directly prove the missing async call caused the assertion failure. Do not change expected error types, stages, trace fields, or wait limits to make them pass.

| Location | Test |
| --- | --- |
| `test/jido/agent_server/observability_redaction_test.exs:16` | cast failure logs and emitted errors sanitize structured secret fields (JidoTest.AgentServer.ObservabilityRedactionTest) |
| `test/jido/agent_server/runtime_boundary_test.exs:161` | error Signal policy reports failure without causing a feedback loop (Jido.AgentServer.RuntimeBoundaryTest) |
| `test/jido/agent_server/runtime_boundary_test.exs:228` | error Signal delivery is bounded and does not block control calls (Jido.AgentServer.RuntimeBoundaryTest) |
| `test/jido/plugin/sensor_manager_test.exs:152` | reuses unchanged sensors and replaces changed configurations (Jido.Plugin.SensorManagerTest) |
| `test/jido/topology/child_runtime_test.exs:118` | a child that never becomes ready does not emit a ready event (Jido.Topology.ChildRuntimeTest) |
| `test/jido/topology/controller_boundary_test.exs:318` | lifecycle Signals reach a stable Ref and describe failed components (Jido.Topology.ControllerBoundaryTest) |
| `test/jido/topology/controller/supervision_test.exs:130` | Bus clients reconnect during manual repair without replacing the Agent (Jido.Topology.Controller.SupervisionTest) |
| `test/jido/agent_server/child_lifecycle_test.exs:465` | parent death policy uses private runtime state (Jido.AgentServer.ChildLifecycleTest) |
| `test/jido/agent_server/runtime_lifecycle_test.exs:131` | Agent death stops its Exec and Action or Flow work (Jido.AgentServer.RuntimeLifecycleTest) |
| `test/jido/agent_server/runtime_lifecycle_test.exs:192` | starts and owns a Plugin runtime child outside Agent state (Jido.AgentServer.RuntimeLifecycleTest) |
| `test/jido/agent_server/public_api_test.exs:230` | keeps status and OTP system requests responsive during a slow turn (Jido.AgentServer.PublicAPITest) |
| `test/jido/agent_server/public_api_test.exs:533` | rejects excess postponed calls with a structured overload error (Jido.AgentServer.PublicAPITest) |
| `test/jido/plugin/heartbeat_test.exs:31` | a runtime-only Plugin can feed Signals into its Agent (Jido.Plugin.HeartbeatTest) |
| `test/jido/persistence_test.exs:326` | restores portable Plugin state and rebuilds its runtime (JidoTest.PersistenceTest) |
| `test/jido/plugin/bus/integration_test.exs:126` | casts normal Bus input into the Agent (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:134` | acknowledges durable input only after ordered Agent commits (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:169` | reattaches a durable subscription after its runtime restarts (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:189` | runtime death stops its pending durable delivery worker (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:213` | delivery worker death keeps its runtime available for retry (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:242` | retries durable input after an Agent turn fails (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:269` | one Agent can own a Bus and consume from it (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/plugin/bus/integration_test.exs:319` | Client reconnects when its owned Bus restarts (Jido.Plugin.Bus.IntegrationTest) |
| `test/jido/telemetry/agent_lifecycle_test.exs:259` | semantic events exclude private errors, context, and nonportable partitions (JidoTest.Telemetry.AgentLifecycleTest) |
| `test/jido/topology/controller_test.exs:41` | sends lifecycle Signals to a normal control Agent route (Jido.Topology.ControllerTest) |
| `test/jido/topology/controller_test.exs:303` | broadcasts each Signal to every member (Jido.Topology.ControllerTest) |
| `test/jido/topology/controller_test.exs:322` | supports more than one Bus subscription on an Agent (Jido.Topology.ControllerTest) |
| `test/jido/topology/controller_test.exs:1017` | repairs a Bus and its subscriptions after a Bus failure (Jido.Topology.ControllerTest) |

## Full baseline failure list

Each test appears once. Line numbers refer to the source at the time of the run.

### Removed execution option

- `test/jido/agent/selection_test.exs:251` — state selects the top-level executable without a continuation (Jido.Agent.SelectionTest)

### Direct local values

- `test/jido/agent/portable_state_test.exs:100` — transition and command candidates permit schema-approved local values (Jido.Agent.PortableStateTest)

### AgentServer execution

- `test/jido/agent/candidate_completeness_test.exs:36` — direct and live Turns reject a candidate that omits a defaulted field (JidoTest.Agent.CandidateCompletenessTest)
- `test/jido/agent/candidate_completeness_test.exs:52` — a candidate can omit a field that has no default (JidoTest.Agent.CandidateCompletenessTest)
- `test/jido/agent/replacement_test.exs:25` — set and complete Action candidates replace a domain field (JidoTest.Agent.ReplacementTest)
- `test/jido/agent/flow_expression_test.exs:101` — Flow expressions commit through AgentServer (Jido.Agent.FlowExpressionTest)
- `test/jido/agent/state_boundary_test.exs:14` — invalid complete state cannot commit or run its effects (Jido.Agent.StateBoundaryTest)
- `test/jido/agent/state_boundary_test.exs:60` — Plugin reductions validate stored output without defaults (Jido.Agent.StateBoundaryTest)
- `test/jido/agent/state_intersection_test.exs:88` — Plugin output preserves nullable fields and cannot fill missing stored fields (Jido.Agent.StateIntersectionTest)
- `test/jido/agent/schema_test.exs:158` — Server rejects an invalid candidate without a commit without Plugins (Jido.Agent.SchemaTest)
- `test/jido/agent/schema_test.exs:171` — a candidate at the root bound commits once without Plugins (Jido.Agent.SchemaTest)
- `test/jido/agent/schema_test.exs:158` — Server rejects an invalid candidate without a commit with owned Plugin state (Jido.Agent.SchemaTest)
- `test/jido/agent/schema_test.exs:171` — a candidate at the root bound commits once with owned Plugin state (Jido.Agent.SchemaTest)
- `test/jido/agent/flow_effects_test.exs:132` — a Flow booking request runs only after the live state commit (Jido.Agent.FlowEffectsTest)
- `test/jido/agent/stateless_directive_test.exs:93` — a handler without a Plugin process sends its result through another Turn (Jido.Agent.StatelessDirectiveTest)
- `test/jido/agent/stateless_directive_test.exs:110` — timeout and task death preserve the commit and stop later dispatch (Jido.Agent.StatelessDirectiveTest)
- `test/jido/agent/turn_evaluation_test.exs:66` — invalid callback Turn sources return errors and preserve the live server (Jido.Agent.TurnEvaluationTest)
- `test/jido/agent/flow_effects_test.exs:166` — all Flow requests reach the caller in order and dispatch once after one commit (Jido.Agent.FlowEffectsTest)
- `test/jido/agent/turn_evaluation_test.exs:122` — direct and live evaluation keep the selected custom Turn fixed (Jido.Agent.TurnEvaluationTest)
- `test/jido/agent/selection_test.exs:94` — declared routes and explicit callback fallback prepare and execute the same Turn (Jido.Agent.SelectionTest)
- `test/jido/agent/selection_test.exs:136` — custom Turn inputs use the same normalization without applying route defaults (Jido.Agent.SelectionTest)
- `test/jido/agent/selection_test.exs:172` — routes without defaults accept empty input in direct and live calls (Jido.Agent.SelectionTest)
- `test/jido/agent/selection_test.exs:238` — custom selection can convert raw Signal data before input validation (Jido.Agent.SelectionTest)
- `test/jido/agent_server/child_operation_task_test.exs:67` — child creation keeps inspections responsive and serializes later Turns (Jido.AgentServer.ChildOperationTaskTest)
- `test/jido/agent_server/child_operation_task_test.exs:101` — a failed start worker preserves uncertainty and accepts the eventual child (Jido.AgentServer.ChildOperationTaskTest)
- `test/jido/agent_server/child_operation_task_test.exs:146` — stop retires an active request while its crashed child is restarting (Jido.AgentServer.ChildOperationTaskTest)
- `test/jido/agent_server/child_operation_task_test.exs:240` — a late local start cannot leave a child after its owner stops (Jido.AgentServer.ChildOperationTaskTest)
- `test/jido/agent_server/context_test.exs:105` — admission exit preserves state and releases the worker (Jido.AgentServer.ContextTest)
- `test/jido/agent_server/execution_context_test.exs:27` — a live Turn overrides caller jido and partition while a direct command keeps them (JidoTest.AgentServer.ExecutionContextTest)
- `test/jido/agent_server/context_test.exs:105` — admission timeout preserves state and releases the worker (Jido.AgentServer.ContextTest)
- `test/jido/agent_server/context_test.exs:197` — the Turn deadline replaces a late preparation error (Jido.AgentServer.ContextTest)
- `test/jido/agent_server/context_test.exs:230` — queued calls retain context when admission is cancelled and excess casts are dropped (Jido.AgentServer.ContextTest)
- `test/jido/agent_server/context_test.exs:280` — admission result releases its monitor and timer (Jido.AgentServer.ContextTest)
- `test/jido/agent_server/context_test.exs:306` — context crosses Plugin admission and execution but is not copied to state or Signals (Jido.AgentServer.ContextTest)
- `test/jido/agent_server/emit_dispatch_test.exs:56` — reports the real post-commit dispatch result (Jido.AgentServer.EmitDispatchTest)
- `test/jido/agent_server/emit_dispatch_test.exs:82` — inherits the Agent Jido scope for a Bus target (Jido.AgentServer.EmitDispatchTest)
- `test/jido/agent_server/emit_dispatch_test.exs:92` — turn failure keeps a state commit when delivery fails (Jido.AgentServer.EmitDispatchTest)
- `test/jido/agent_server/supervision_test.exs:7` — a child specification fixes generated identity across OTP restarts (Jido.AgentServer.SupervisionTest)
- `test/jido/agent_server/supervision_test.exs:36` — current definition replaces saved runtime configuration with runtime recovery (Jido.AgentServer.SupervisionTest)
- `test/jido/agent_server/supervision_test.exs:36` — current definition replaces saved runtime configuration with durable recovery (Jido.AgentServer.SupervisionTest)
- `test/jido/agent_server/supervision_test.exs:78` — current definition rejects saved state that does not pass its schema (Jido.AgentServer.SupervisionTest)
- `test/jido/agent_server/runtime_checkpoint_test.exs:45` — local restart copies values but does not recreate resources or transfer ownership (JidoTest.AgentServer.RuntimeCheckpointTest)
- `test/jido/agent_server/runtime_checkpoint_test.exs:99` — clean stop and instance loss remove local runtime checkpoints (JidoTest.AgentServer.RuntimeCheckpointTest)
- `test/jido/agent_server/runtime_checkpoint_test.exs:122` — a committed Agent cannot restart from initial state while its store is unavailable (JidoTest.AgentServer.RuntimeCheckpointTest)
- `test/jido/persistence/indeterminate_write_test.exs:37` — a confirmed write commits state and permits post-commit output (JidoTest.Persistence.IndeterminateWriteTest)
- `test/jido/persistence/indeterminate_write_test.exs:57` — an uncertain reply can follow a stored write without dispatching its Directive (JidoTest.Persistence.IndeterminateWriteTest)
- `test/jido/persistence/indeterminate_write_test.exs:69` — an indeterminate write prevents evaluation of the next Action on stale state (JidoTest.Persistence.IndeterminateWriteTest)
- `test/jido/persistence/indeterminate_write_test.exs:87` — a raised callback after storage also prevents later Action evaluation (JidoTest.Persistence.IndeterminateWriteTest)
- `test/jido/agent_server/failure_contract_test.exs:247` — a hibernation wait timeout does not cancel the active Turn (Jido.AgentServer.FailureContractTest)
- `test/jido/agent_server/failure_contract_test.exs:290` — readiness timeout leaves a queued Signal available after readiness completes (Jido.AgentServer.FailureContractTest)
- `test/jido/agent_server/failure_contract_test.exs:335` — error Signal delivery error preserves state and records one failure (Jido.AgentServer.FailureContractTest)
- `test/jido/agent_server/failure_contract_test.exs:335` — error Signal delivery kill preserves state and records one failure (Jido.AgentServer.FailureContractTest)
- `test/jido/instance_ref_test.exs:119` — a Registry restart preserves one live Agent identity and Ref resolution (JidoTest.InstanceRefTest)
- `test/jido/instance_ref_test.exs:253` — a generated instance exposes the same Ref-first facade (JidoTest.InstanceRefTest)
- `test/jido/instance_ref_test.exs:263` — the Ref facade resolves each operation and preserves direct Server results (JidoTest.InstanceRefTest)
- `test/jido/instance_ref_test.exs:304` — a durable Ref survives rebinding its namespace to another local instance (JidoTest.InstanceRefTest)
- `test/jido/persistence/live_state_test.exs:213` — live execution commits local domain and Plugin values without persistence (JidoTest.Persistence.LiveStateTest)
- `test/jido/persistence/live_state_test.exs:239` — persistent custom and Plugin commits convert before storage and dispatch (JidoTest.Persistence.LiveStateTest)
- `test/jido/persistence/live_state_test.exs:259` — checkpoint, conversion, and storage failures neither commit nor dispatch (JidoTest.Persistence.LiveStateTest)
- `test/jido/plugin/audit_test.exs:105` — commits bounded audit records with domain state (Jido.Plugin.AuditTest)
- `test/jido/plugin/audit_test.exs:121` — rejects non-portable audit data before commit (Jido.Plugin.AuditTest)
- `test/jido/plugin/audit_test.exs:147` — rejects a non-byte audit event before the complete candidate commits (Jido.Plugin.AuditTest)
- `test/jido/plugin/preparation_test.exs:122` — live execution uses the same pure preparation (Jido.Plugin.PreparationTest)
- `test/jido/plugin/sensor_manager_test.exs:92` — reconciles desired sensors and restarts a failed sensor (Jido.Plugin.SensorManagerTest)
- `test/jido/plugin/sensor_manager_test.exs:127` — restores sensors when an internal supervisor fails (Jido.Plugin.SensorManagerTest)
- `test/jido/agent_server/runtime_boundary_test.exs:65` — Jido.Exec execution can exceed the Directive timeout (Jido.AgentServer.RuntimeBoundaryTest)
- `test/jido/agent_server/runtime_boundary_test.exs:95` — a waiting custom policy can query its Server while later Signals and stop run (Jido.AgentServer.RuntimeBoundaryTest)
- `test/jido/agent_server/runtime_boundary_test.exs:325` — Directive count limits reject the candidate before commit (Jido.AgentServer.RuntimeBoundaryTest)
- `test/jido/topology/child_runtime_test.exs:55` — the first command can publish an exported event (Jido.Topology.ChildRuntimeTest)
- `test/jido/topology/child_runtime_test.exs:69` — a Bus activated after its child member exports its first event (Jido.Topology.ChildRuntimeTest)
- `test/jido/topology/child_runtime_test.exs:78` — a replacement Bus exports direct publication before another child command (Jido.Topology.ChildRuntimeTest)
- `test/jido/topology/child_runtime_test.exs:97` — gate recovery attaches once to a Bus that stays alive (Jido.Topology.ChildRuntimeTest)
- `test/jido/plugin/sensor_manager_test.exs:298` — rejects non-byte sensor config before commit or resource startup (Jido.Plugin.SensorManagerTest)
- `test/jido/topology/controller_boundary_test.exs:44` — local placement validates targets and options without replacing a live Agent (Jido.Topology.ControllerBoundaryTest)
- `test/jido/topology/controller_boundary_test.exs:148` — a rejected durable placement write keeps the old Agent and state live (Jido.Topology.ControllerBoundaryTest)
- `test/jido/topology/controller_boundary_test.exs:179` — a restarted Controller finishes an accepted pending placement (Jido.Topology.ControllerBoundaryTest)
- `test/jido/topology/controller_boundary_test.exs:214` — saved placement survives a worker restart and drops keys outside the plan (Jido.Topology.ControllerBoundaryTest)
- `test/jido/topology/controller_update_test.exs:83` — an additive update retains existing Agents and becomes the repair target (JidoTest.Topology.ControllerUpdateTest)
- `test/jido/topology/runtime_checkpoint_test.exs:9` — runtime failure keeps committed director and member state (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:9` — director failure keeps committed director and member state (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:9` — controller failure keeps committed director and member state (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:24` — clean stop clears a checkpoint whose member is dormant after Runtime recovery (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:39` — runtime failure keeps nested child state and clean stop clears it (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:39` — director failure keeps nested child state and clean stop clears it (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:56` — clean parent stop clears nested checkpoints while the child branch is dormant (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:70` — a clean child stop clears checkpoints after its GateServer restarts (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:93` — a parent never waits for or deletes an independent Runtime at its declared child ID (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:133` — definition preparation validates and resets the RuntimeCheckpoint fallback (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_checkpoint_test.exs:237` — preserve activation updates the RuntimeCheckpoint before immediate Hibernate (Jido.Topology.RuntimeCheckpointTest)
- `test/jido/topology/runtime_hibernate_test.exs:73` — running Hibernate checkpoints, stays asleep through repair, and a call thaws it (Jido.Topology.RuntimeHibernateTest)
- `test/jido/topology/runtime_hibernate_test.exs:125` — a call thaws the target and its hibernated dependencies (Jido.Topology.RuntimeHibernateTest)
- `test/jido/topology/runtime_hibernate_test.exs:226` — a persistence failure keeps the member available (Jido.Topology.RuntimeHibernateTest)
- `test/jido/topology/controller/supervision_test.exs:60` — OTP restores committed state and runtime inputs while the coordinator is paused (Jido.Topology.Controller.SupervisionTest)
- `test/jido/topology/controller/supervision_test.exs:108` — a coordinator crash preserves Agent, Bus, and Plugin PIDs and state (Jido.Topology.Controller.SupervisionTest)
- `test/jido/topology/runtime_test.exs:27` — a lazy runtime adds and reports one neutral Agent definition (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_test.exs:63` — a lazy runtime removes one dynamic root Agent definition (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_test.exs:105` — a headless DSL runtime starts only the requested dependency closure (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_hibernate_test.exs:497` — Hibernate waits for a Gateway-admitted call before it checkpoints (Jido.Topology.RuntimeHibernateTest)
- `test/jido/topology/runtime_hibernate_test.exs:535` — a Hibernate deadline during admitted work is indeterminate and does not stop later (Jido.Topology.RuntimeHibernateTest)
- `test/jido/topology/runtime_test.exs:147` — a waiting first call permits automatic repair after a start failure (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_test.exs:245` — an eager child group is owned and an existing root cannot be adopted (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_test.exs:274` — a coordinator restart retains lazy selection and healthy member PIDs (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_test.exs:301` — an unavailable target does not block healthy calls and degrades the parent gate (Jido.Topology.RuntimeTest)
- `test/jido/topology/runtime_test.exs:334` — a clean child stop stays failed and a later call cannot start it again (Jido.Topology.RuntimeTest)
- `test/jido/topology/controller/supervision_test.exs:205` — hibernation stays stopped and retains the durable commit (Jido.Topology.Controller.SupervisionTest)
- `test/jido/topology/controller/supervision_test.exs:242` — failed restart bootstrap stays stopped and preserves the prior checkpoint (Jido.Topology.Controller.SupervisionTest)
- `test/jido/agent_server/commit_boundary_test.exs:93` — three Directives run in returned order after one complete commit (Jido.AgentServer.CommitBoundaryTest)
- `test/jido/agent_server/commit_boundary_test.exs:107` — a Directive timeout can follow an external effect and cannot undo the commit (Jido.AgentServer.CommitBoundaryTest)
- `test/jido/agent_server/commit_boundary_test.exs:144` — external Action work remains when candidate validation fails before storage (Jido.AgentServer.CommitBoundaryTest)
- `test/jido/agent_server/commit_boundary_test.exs:168` — an ordinary Directive batch is not replayed after loss at index 0 (Jido.AgentServer.CommitBoundaryTest)
- `test/jido/agent_server/commit_boundary_test.exs:168` — an ordinary Directive batch is not replayed after loss at index 1 (Jido.AgentServer.CommitBoundaryTest)
- `test/jido/agent_server/child_lifecycle_test.exs:125` — spawns, addresses, and stops a child Agent without putting runtime refs in state (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:174` — a child sends a domain result to its parent as a later Signal (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:202` — an asynchronously prepared child target uses the restarted child PID (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:251` — an asynchronously prepared parent target observes parent loss (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:359` — child factories must preserve requested identity before tracking (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:486` — parent death cancels active Jido.Exec work (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:526` — a transient child does not restart after its parent stops (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:552` — a permanent child cannot restart after a normal parent death under stop (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:552` — a permanent child cannot restart after a kill parent death under stop (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:552` — a permanent child cannot restart after a normal parent death under continue (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:552` — a permanent child cannot restart after a kill parent death under continue (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:552` — a permanent child cannot restart after a normal parent death under emit_orphan (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:552` — a permanent child cannot restart after a kill parent death under emit_orphan (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/child_lifecycle_test.exs:612` — a parent tracks the new PID after an abnormal child restart (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/directive_execution_test.exs:28` — commits Agent state before it emits a follow-up Signal (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:46` — rejects an invalid built-in Directive before the Agent commit (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:60` — SpawnProcess faults settle after commit without killing the Agent Server (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:116` — rejects an invalid Emit dispatch before the Agent commit (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:145` — validates a Plugin Directive once in a live turn (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:161` — keeps the Server responsive during Plugin Directive dispatch (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:176` — Directive task exit retains the commit and ignores stale timeouts (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:231` — times out owned Plugin Directive work and records exact progress (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:271` — a supervised Agent stop terminates owned Directive work (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:283` — rejects a synchronous call from Plugin Directive dispatch (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:300` — keeps the commit but stops a Directive batch after a runtime failure (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:349` — waits for external Emit results and skips later Directives after failure (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:396` — counts consecutive post-commit Directive failures (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/directive_execution_test.exs:433` — does not restart stale state after a post-commit Directive failure (Jido.AgentServer.DirectiveExecutionTest)
- `test/jido/agent_server/effect_recovery_test.exs:100` — completed IDs prevent duplicate delivery and conflicting state changes (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:136` — restore resumes saved work after a crash at before_write (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:136` — restore resumes saved work after a crash at after_write (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:171` — completed work remains complete after another Agent activation (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:191` — Plugin loss restarts delivery without replacing the Agent (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:215` — a blocked delivery permits new Turns and preserves older pending work (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:241` — an unavailable sink is retried from saved intent (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:259` — a failed intent write exposes no work to the live Plugin (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent_server/effect_recovery_test.exs:281` — a failed completion write retains intent for a restored activation (Jido.AgentServer.EffectRecoveryTest)
- `test/jido/agent/authoring_test.exs:884` — generated Action and Flow helpers commit the direct candidate (JidoTest.Agent.AuthoringRuntimeTest)
- `test/jido/agent/authoring_test.exs:920` — generated inline helpers apply route defaults (JidoTest.Agent.AuthoringRuntimeTest)
- `test/jido/agent/authoring_test.exs:931` — a live helper forwards runtime validation without a commit (JidoTest.Agent.AuthoringRuntimeTest)
- `test/jido/agent/authoring_test.exs:950` — helpers leave executable validation to execution (JidoTest.Agent.AuthoringRuntimeTest)
- `test/jido/agent_server/pending_job_recovery_test.exs:71` — a saved approval request survives Agent loss (Jido.AgentServer.PendingJobRecoveryTest)
- `test/jido/agent_server/pending_job_recovery_test.exs:94` — agent loss permits explicit retry and rejects the old result (Jido.AgentServer.PendingJobRecoveryTest)
- `test/jido/agent_server/pending_job_recovery_test.exs:94` — plugin loss permits explicit retry and rejects the old result (Jido.AgentServer.PendingJobRecoveryTest)
- `test/jido/agent_server/pending_job_recovery_test.exs:145` — cancellation survives restart and rejects approval, retry, and late results (Jido.AgentServer.PendingJobRecoveryTest)
- `test/jido/agent_server/after_commit_test.exs:49` — notifies in declaration order, with exact owned revisions, before Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:92` — unchanged Turns advance the revision and stateless hooks receive nil (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:125` — hooks keep inspections responsive and serialize Turns (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:152` — a hook cannot call another Turn on its owner (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:186` — storage rejection does not notify (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:212` — error settles after commit and skips remaining hooks and Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:212` — raise settles after commit and skips remaining hooks and Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:212` — throw settles after commit and skips remaining hooks and Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:212` — exit settles after commit and skips remaining hooks and Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:212` — kill settles after commit and skips remaining hooks and Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:212` — invalid settles after commit and skips remaining hooks and Directives (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:264` — timeout kills the task and preserves the saved commit (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:302` — runtime replacement and restore rebuild the exact view without replay (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:341` — infinity still bounds a hook and old task messages cannot settle a later Turn (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:366` — hard owner loss kills a hook and restore does not replay it (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:401` — stop-on-error stops after the caller receives the successful commit (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:425` — hook failure emits a valid error Signal and keeps the committed Server alive (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:459` — hook failure logs contain bounded identity and no raw callback error (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/after_commit_test.exs:477` — owner shutdown kills a blocked task and balances its span (Jido.AgentServer.AfterCommitTest)
- `test/jido/agent_server/runtime_observability_test.exs:9` — records bounded debug events without exposing Server state (Jido.AgentServer.RuntimeObservabilityTest)
- `test/jido/agent_server/runtime_observability_test.exs:42` — a Stop Directive commits once and does not restart a supervised Agent (Jido.AgentServer.RuntimeObservabilityTest)
- `test/jido/agent_server/runtime_observability_test.exs:61` — normalizes an arbitrary Stop reason so stale state cannot restart (Jido.AgentServer.RuntimeObservabilityTest)
- `test/jido/agent_server/runtime_observability_test.exs:80` — rejects a Stop Directive before later effects (Jido.AgentServer.RuntimeObservabilityTest)
- `test/jido/agent_server/runtime_observability_test.exs:97` — emits semantic Turn and Directive telemetry with bounded metadata (Jido.AgentServer.RuntimeObservabilityTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:69` — owns Action and Flow execution under the Agent Jido instance (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:98` — unowned messages do not interrupt Jido.Exec after attachment handling (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:265` — Plugin child lookup stays responsive while restart readiness reads Agent state (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:298` — refreshes Plugin state and readiness after an internal runtime restart (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:333` — restores the last committed Agent when a required Plugin runtime is lost (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/public_api_test.exs:52` — commits one terminal Action output as one complete Agent state (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:90` — keeps executable input separate from committed Agent state (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:104` — caller context reaches one Turn without changing its Signal or Agent (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:191` — runs an Action continuation chain before the single commit (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:200` — runs one multi-step Flow as one turn (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:217` — runs a Dispatch continuation inside one Flow turn (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:255` — rejects a synchronous call from the active executable process (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:269` — postpones later Signals in sender order without a private Signal queue (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:294` — does not cancel a started turn when its caller times out (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:329` — reports Exec and finalization failures without changing the Agent (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:381` — cancels active Exec work without a commit (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:422` — one Server Turn timeout cancels execution and rejects its late result (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:469` — completion before cancellation keeps the commit and rejects the stale Turn id (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:558` — rejects non-core Directives before commit (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/upgrade_test.exs:88` — a quiescent operation runs after the active Turn finishes (JidoTest.AgentServer.UpgradeTest)
- `test/jido/agent_server/upgrade_test.exs:186` — a checkpoint keeps the upgrade origin after a later Turn (JidoTest.AgentServer.UpgradeTest)
- `test/jido/persistence/conformance/local_test.exs:48` — Agent creates revision zero and stores every successful Turn (JidoTest.Persistence.Conformance.Local.Ets)
- `test/jido/persistence/conformance/local_test.exs:48` — hibernate and required restore keep state and revision (JidoTest.Persistence.Conformance.Local.Ets)
- `test/jido/persistence/conformance/local_test.exs:49` — a rejected prewrite keeps the prior durable revision (JidoTest.Persistence.Conformance.Local.Ets)
- `test/jido/persistence/conformance/local_test.exs:49` — a lost reply stops stale work and restores the stored candidate (JidoTest.Persistence.Conformance.Local.Ets)
- `test/jido/persistence/conformance/local_test.exs:48` — Agent creates revision zero and stores every successful Turn (JidoTest.Persistence.Conformance.Local.File)
- `test/jido/persistence/conformance/local_test.exs:48` — hibernate and required restore keep state and revision (JidoTest.Persistence.Conformance.Local.File)
- `test/jido/persistence/conformance/local_test.exs:49` — a rejected prewrite keeps the prior durable revision (JidoTest.Persistence.Conformance.Local.File)
- `test/jido/persistence/conformance/local_test.exs:49` — a lost reply stops stale work and restores the stored candidate (JidoTest.Persistence.Conformance.Local.File)
- `test/jido/persistence/conformance/local_test.exs:48` — Agent creates revision zero and stores every successful Turn (JidoTest.Persistence.Conformance.Local.Mnesia)
- `test/jido/persistence/conformance/local_test.exs:48` — hibernate and required restore keep state and revision (JidoTest.Persistence.Conformance.Local.Mnesia)
- `test/jido/persistence/conformance/local_test.exs:49` — a rejected prewrite keeps the prior durable revision (JidoTest.Persistence.Conformance.Local.Mnesia)
- `test/jido/persistence/conformance/local_test.exs:49` — a lost reply stops stale work and restores the stored candidate (JidoTest.Persistence.Conformance.Local.Mnesia)
- `test/jido/persistence/conformance/local_test.exs:48` — Agent creates revision zero and stores every successful Turn (JidoTest.Persistence.Conformance.Local.EctoSqlite)
- `test/jido/persistence/conformance/local_test.exs:48` — hibernate and required restore keep state and revision (JidoTest.Persistence.Conformance.Local.EctoSqlite)
- `test/jido/persistence/conformance/local_test.exs:49` — a rejected prewrite keeps the prior durable revision (JidoTest.Persistence.Conformance.Local.EctoSqlite)
- `test/jido/persistence/conformance/local_test.exs:49` — a lost reply stops stale work and restores the stored candidate (JidoTest.Persistence.Conformance.Local.EctoSqlite)
- `test/jido/plugin/authoring_runtime_test.exs:94` — JidoTest.CommitProjection.First preserves commit order, state, and failed-Turn isolation (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:119` — JidoTest.CommitProjection.First error skips later hooks and Directives after successful commit (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:119` — JidoTest.CommitProjection.First timeout skips later hooks and Directives after successful commit (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:94` — Jido.Plugin.AuthoringRuntimeTest.LocalFirst preserves commit order, state, and failed-Turn isolation (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:119` — Jido.Plugin.AuthoringRuntimeTest.LocalFirst error skips later hooks and Directives after successful commit (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:119` — Jido.Plugin.AuthoringRuntimeTest.LocalFirst timeout skips later hooks and Directives after successful commit (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:177` — Jido.Plugin.AuthoringRuntimeTest.DelegatedRuntime gates readiness, replaces with fresh state, and stops its runtime (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/plugin/authoring_runtime_test.exs:177` — Jido.Plugin.AuthoringRuntimeTest.LocalRuntime gates readiness, replaces with fresh state, and stops its runtime (Jido.Plugin.AuthoringRuntimeTest)
- `test/jido/persistence_test.exs:469` — writes every successful commit and preserves the Server revision (JidoTest.PersistenceTest)
- `test/jido/persistence_test.exs:491` — hibernate persists and stops an idle Agent Server (JidoTest.PersistenceTest)
- `test/jido/persistence_test.exs:515` — a persistence conflict removes the stale Server's write authority (JidoTest.PersistenceTest)
- `test/jido/persistence_test.exs:555` — thaw restores, starts, and rebuilds Plugin runtimes (JidoTest.PersistenceTest)
- `test/jido/plugin/scheduler/live_runtime_test.exs:25` — delayed and cron Signals return through the Agent mailbox (Jido.Plugin.Scheduler.LiveRuntimeTest)
- `test/jido/plugin/scheduler/live_runtime_test.exs:105` — reduces Scheduler changes in list order and reconciles the final state (Jido.Plugin.Scheduler.LiveRuntimeTest)
- `test/jido/plugin/scheduler/live_runtime_test.exs:134` — restarts the Scheduler runtime from committed Plugin state (Jido.Plugin.Scheduler.LiveRuntimeTest)
- `test/jido/plugin/scheduler/live_runtime_test.exs:168` — the Scheduler runtime restarts a failed cron Job (Jido.Plugin.Scheduler.LiveRuntimeTest)
- `test/jido/plugin/scheduler/occurrence_runtime_test.exs:43` — runtime ticks carry a logical occurrence ID independent of Signal delivery (Jido.Plugin.Scheduler.OccurrenceRuntimeTest)
- `test/jido/plugin/scheduler/occurrence_runtime_test.exs:72` — repeated clock slots keep identity while generation replacement changes it (Jido.Plugin.Scheduler.OccurrenceRuntimeTest)
- `test/jido/plugin/scheduler/occurrence_runtime_test.exs:99` — Scheduler restart retains the occurrence coordinates (Jido.Plugin.Scheduler.OccurrenceRuntimeTest)
- `test/jido/plugin/scheduler/occurrence_runtime_test.exs:118` — Agent restore retains identity and the next scheduled instant changes it (Jido.Plugin.Scheduler.OccurrenceRuntimeTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84` — an uncommitted occurrence is retried after Agent loss and clock advance (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:110` — completion survives Agent loss after its file write and does not repeat (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:133` — Scheduler loss during delivery does not lose or repeat the business commit (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:160` — a failed intent write preserves state for a restored activation (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:160` — a failed result write preserves state for a restored activation (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:191` — failed delivery preserves saved work for reactivation (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/scheduler/occurrence_recovery_test.exs:221` — cancelling pending work survives restore and rejects the old delivery (Jido.Plugin.Scheduler.OccurrenceRecoveryTest)
- `test/jido/plugin/state_runtime_test.exs:77` — state-only Plugin Directives update state without a Plugin runtime (Jido.Plugin.StateRuntimeTest)
- `test/jido/topology/controller/resource_race_test.exs:9` — one manual repair accepts the Bus restarted by its resource supervisor (Jido.Topology.Controller.ResourceRaceTest)
- `test/jido/topology/authoring_host_test.exs:79` — one host composes Agent and Topology DSLs and keeps constructor meanings (JidoTest.Topology.AuthoringHostTest)
- `test/jido/telemetry/open_telemetry_test.exs:362` — live Plugin notifications are children of their Turn for local and carrier Signals (JidoTest.Telemetry.OpenTelemetryTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:31` — an external telemetry handler failure preserves the command result (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:60` — each admitted Turn emits a terminal event with its Outcome and revision (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:196` — commit ends the Turn span and held delivery delays settlement (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:305` — Directive timeout reports a committed terminal outcome (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:342` — a requested stop settles active work once before lifecycle completion (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:383` — rejected calls and casts report bounded admission facts (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:453` — an expired postponed call reports deadline rejection (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:558` — a crashed Directive task emits an exception and one terminal outcome (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/topology/controller/composition_runtime_test.exs:136` — status stays responsive and independent members start while readiness is blocked (Jido.Topology.Controller.CompositionRuntimeTest)
- `test/jido/topology/controller/composition_runtime_test.exs:324` — a team stop leaves the shared Bus and the other team running (Jido.Topology.Controller.CompositionRuntimeTest)
- `test/jido/topology/controller/composition_runtime_test.exs:358` — saved component state and shared Bus subscriptions survive controller restart (Jido.Topology.Controller.CompositionRuntimeTest)
- `test/jido/topology/runtime_ownership_test.exs:39` — root replacement waits for an old child Gate to finish shutdown (Jido.Topology.RuntimeOwnershipTest)
- `test/jido/topology/controller_test.exs:84` — starts independent agents, preserves committed state, and cleans up (Jido.Topology.ControllerTest)
- `test/jido/topology/controller_test.exs:948` — restores committed state and Bus subscriptions after controller shutdown (Jido.Topology.ControllerTest)
- `test/jido/topology/controller_test.exs:1049` — a controller worker crash retains owned agents and their state (Jido.Topology.ControllerTest)
- `test/jido/tracing/causal_trace_test.exs:42` — work and result Turns retain one trace and distinct causal spans (JidoTest.Tracing.CausalTraceTest)
- `test/jido/tracing/causal_trace_test.exs:69` — child-start Turns retain the trace of the spawning parent Turn (JidoTest.Tracing.CausalTraceTest)
- `test/jido/tracing/causal_trace_test.exs:86` — child activation and notification expose the cause without changing source identity (JidoTest.Tracing.CausalTraceTest)
- `test/jido/tracing/causal_trace_test.exs:118` — local OTP restart retains its cause and replacement uses a new cause (JidoTest.Tracing.CausalTraceTest)
- `test/jido/tracing/causal_trace_test.exs:184` — local restore retains the runtime binding cause (JidoTest.Tracing.CausalTraceTest)
- `test/jido/tracing/causal_trace_test.exs:221` — a restored relationship without a recorded cause keeps root behavior (JidoTest.Tracing.CausalTraceTest)
- `test/jido/tracing/causal_trace_test.exs:254` — a later child command uses its own trace and an explicit retry retains its cause (JidoTest.Tracing.CausalTraceTest)

### Live execution follow-up

- `test/jido/agent_server/observability_redaction_test.exs:16` — cast failure logs and emitted errors sanitize structured secret fields (JidoTest.AgentServer.ObservabilityRedactionTest)
- `test/jido/agent_server/runtime_boundary_test.exs:161` — error Signal policy reports failure without causing a feedback loop (Jido.AgentServer.RuntimeBoundaryTest)
- `test/jido/agent_server/runtime_boundary_test.exs:228` — error Signal delivery is bounded and does not block control calls (Jido.AgentServer.RuntimeBoundaryTest)
- `test/jido/plugin/sensor_manager_test.exs:152` — reuses unchanged sensors and replaces changed configurations (Jido.Plugin.SensorManagerTest)
- `test/jido/topology/child_runtime_test.exs:118` — a child that never becomes ready does not emit a ready event (Jido.Topology.ChildRuntimeTest)
- `test/jido/topology/controller_boundary_test.exs:318` — lifecycle Signals reach a stable Ref and describe failed components (Jido.Topology.ControllerBoundaryTest)
- `test/jido/topology/controller/supervision_test.exs:130` — Bus clients reconnect during manual repair without replacing the Agent (Jido.Topology.Controller.SupervisionTest)
- `test/jido/agent_server/child_lifecycle_test.exs:465` — parent death policy uses private runtime state (Jido.AgentServer.ChildLifecycleTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:131` — Agent death stops its Exec and Action or Flow work (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/runtime_lifecycle_test.exs:192` — starts and owns a Plugin runtime child outside Agent state (Jido.AgentServer.RuntimeLifecycleTest)
- `test/jido/agent_server/public_api_test.exs:230` — keeps status and OTP system requests responsive during a slow turn (Jido.AgentServer.PublicAPITest)
- `test/jido/agent_server/public_api_test.exs:533` — rejects excess postponed calls with a structured overload error (Jido.AgentServer.PublicAPITest)
- `test/jido/plugin/heartbeat_test.exs:31` — a runtime-only Plugin can feed Signals into its Agent (Jido.Plugin.HeartbeatTest)
- `test/jido/persistence_test.exs:326` — restores portable Plugin state and rebuilds its runtime (JidoTest.PersistenceTest)
- `test/jido/plugin/bus/integration_test.exs:126` — casts normal Bus input into the Agent (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:134` — acknowledges durable input only after ordered Agent commits (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:169` — reattaches a durable subscription after its runtime restarts (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:189` — runtime death stops its pending durable delivery worker (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:213` — delivery worker death keeps its runtime available for retry (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:242` — retries durable input after an Agent turn fails (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:269` — one Agent can own a Bus and consume from it (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/plugin/bus/integration_test.exs:319` — Client reconnects when its owned Bus restarts (Jido.Plugin.Bus.IntegrationTest)
- `test/jido/telemetry/agent_lifecycle_test.exs:259` — semantic events exclude private errors, context, and nonportable partitions (JidoTest.Telemetry.AgentLifecycleTest)
- `test/jido/topology/controller_test.exs:41` — sends lifecycle Signals to a normal control Agent route (Jido.Topology.ControllerTest)
- `test/jido/topology/controller_test.exs:303` — broadcasts each Signal to every member (Jido.Topology.ControllerTest)
- `test/jido/topology/controller_test.exs:322` — supports more than one Bus subscription on an Agent (Jido.Topology.ControllerTest)
- `test/jido/topology/controller_test.exs:1017` — repairs a Bus and its subscriptions after a Bus failure (Jido.Topology.ControllerTest)
