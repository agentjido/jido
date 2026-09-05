> Current acceptance runs, 2026-09-05: [ten feature probes](feature-acceptance-results.md)
> and [three live-upgrade examples](live-upgrade-results.md) have 34 passing
> checks and 11 failing checks across nine proposed core features. All 45 checks
> are enabled. These reports supersede older research counts for these targets.

> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the migration guide](../../guides/migration.md) for current API changes.

# Example feature catalog

The main sequence has **47 SDK feature fixtures**. Each adds a capability to
the previous groups. Source folders, test folders, and current profiles share
the same `CC_EE_name` ID. Runtime and Multi-agent IDs were deliberately revised
on 2026-09-04 to make the learning order clear.

Research is now a queue of **eight unresolved capabilities**. Seven solved
capabilities have moved into Runtime and Multi-agent. The 48 old application
and adapter fixtures were removed from the runnable tree; their 54 original
profiles remain in the archive and their source is available at commit
`bd05a32`. The
[research map](runtime-multi-agent-research.md) maps every old ID to a current
feature or a capability target.

| Group | Fixtures | Passing tests | Existing skips |
| --- | ---: | ---: | ---: |
| Basic | 5 | 22 | 0 |
| Workflow | 9 | 35 | 0 |
| LLM | 10 | 66 | 0 |
| Runtime | 13 | 93 | 0 |
| Multi-agent | 6 | 38 | 0 |
| Factory | 4 | 57 | 0 |
| Research queue | 8 | 7 passing, 4 enabled failures | 0 |

Main-group tests include local SDK integration and two-node core acceptance
tests. Local model and service fixtures do not prove live provider
compatibility. Runtime and Multi-agent have no skips. Seven capability targets
have working examples and passing tests.
[REC-03](rec-03-results.md) has 25 passing identity and recovery tests, including
the formerly failing crash probe. [OBS-02](obs-02-results.md) has 12 tests for
local/remote causation, failure, retry, and restart. [DIST-03](dist-03-results.md)
has one passing proof and one enabled cluster-ownership failure. Four targets
remain plans. The three [persistence probes](persistence-boundary-results.md)
add six passing controls and three enabled failures at the core adapter boundary.

## Basic

| ID | Example | Status | Test class |
| --- | --- | --- | --- |
| `01_01_minimal_agent` | [Minimal Agent](profiles/01_basic/01_01_minimal_agent.md) | implemented | local deterministic |
| `01_02_typed_command_agent` | [Typed Command Agent](profiles/01_basic/01_02_typed_command_agent.md) | implemented | local deterministic |
| `01_03_plugin_state_agent` | [Plugin State Agent](profiles/01_basic/01_03_plugin_state_agent.md) | implemented | local deterministic |
| `01_04_directive_agent` | [Directive Agent](profiles/01_basic/01_04_directive_agent.md) | implemented | local deterministic |
| `01_05_controlled_turn_agent` | [Controlled Turn Agent](profiles/01_basic/01_05_controlled_turn_agent.md) | implemented | local deterministic |

## Workflow

| ID | Example | Status | Test class |
| --- | --- | --- | --- |
| `02_01_sequential_flow` | [Sequential Flow](profiles/02_workflow/02_01_sequential_flow.md) | implemented | local deterministic |
| `02_02_effectful_steps` | [Effectful Steps](profiles/02_workflow/02_02_effectful_steps.md) | implemented | local deterministic |
| `02_03_conditional_routes` | [Conditional Routes](profiles/02_workflow/02_03_conditional_routes.md) | implemented | local deterministic |
| `02_04_parallel_join` | [Parallel Join](profiles/02_workflow/02_04_parallel_join.md) | implemented | local deterministic |
| `02_05_ordered_batch` | [Ordered Batch](profiles/02_workflow/02_05_ordered_batch.md) | implemented | local deterministic |
| `02_06_bounded_iteration` | [Bounded Iteration](profiles/02_workflow/02_06_bounded_iteration.md) | implemented | local deterministic |
| `02_07_nested_flow` | [Nested Flow](profiles/02_workflow/02_07_nested_flow.md) | implemented | local deterministic |
| `02_08_executable_continuation` | [Executable Continuation](profiles/02_workflow/02_08_executable_continuation.md) | implemented | local deterministic |
| `02_09_approval_workflow` | [Approval Workflow](profiles/02_workflow/02_09_approval_workflow.md) | implemented | local deterministic |

## LLM

| ID | Example | Status | Test class |
| --- | --- | --- | --- |
| `03_01_model_response` | [Model Response](profiles/03_llm/03_01_model_response.md) | implemented | local deterministic |
| `03_02_conversation_history` | [Conversation History](profiles/03_llm/03_02_conversation_history.md) | implemented | local deterministic |
| `03_03_tool_call` | [Tool Call](profiles/03_llm/03_03_tool_call.md) | implemented | local deterministic |
| `03_04_tool_loop` | [Tool Loop](profiles/03_llm/03_04_tool_loop.md) | implemented | local deterministic |
| `03_05_parallel_tools` | [Parallel Tools](profiles/03_llm/03_05_parallel_tools.md) | implemented | local deterministic |
| `03_06_grounded_answer` | [Grounded Answer](profiles/03_llm/03_06_grounded_answer.md) | implemented | local deterministic |
| `03_07_output_repair` | [Output Repair](profiles/03_llm/03_07_output_repair.md) | implemented | local deterministic |
| `03_08_context_compaction` | [Context Compaction](profiles/03_llm/03_08_context_compaction.md) | implemented | local deterministic |
| `03_09_subagent_delegation` | [Subagent Delegation](profiles/03_llm/03_09_subagent_delegation.md) | implemented | local deterministic |
| `03_10_recursive_analysis` | [Recursive Analysis](profiles/03_llm/03_10_recursive_analysis.md) | implemented | local deterministic |

## Runtime

| ID | Example | Added feature |
| --- | --- | --- |
| `04_01_scheduled_signals` | [Scheduled Signals](profiles/04_runtime/04_01_scheduled_signals.md) | A Scheduler Directive produces a later Signal and a separate commit. |
| `04_02_keyed_timers` | [Keyed Timers](profiles/04_runtime/04_02_keyed_timers.md) | An example Plugin replaces one keyed timer, ignores stale generations, and flushes one ordered batch. |
| `04_03_bus_delivery` | [Bus Delivery](profiles/04_runtime/04_03_bus_delivery.md) | A real Bus Client delivers ordered records, retries failed Turns, and acknowledges after commit. |
| `04_04_managed_jobs` | [Managed Jobs](profiles/04_runtime/04_04_managed_jobs.md) | An Agent-owned Plugin starts a linked task after commit and sends a later terminal Signal. |
| `04_05_runtime_inspection` | [Runtime Inspection](profiles/04_runtime/04_05_runtime_inspection.md) | Public inspection exposes committed state and its matching revision while work is active. |
| `04_06_state_recovery` | [State Recovery](profiles/04_runtime/04_06_state_recovery.md) | A restored Agent retains its complete state, duplicate ledger, and commit revision. |
| `04_07_input_deduplication` | [Input Deduplication](profiles/04_runtime/04_07_input_deduplication.md) | A stable input ID rejects duplicate work before a new commit; invalid input consumes no ID. |
| `04_08_commit_outbox` | [Commit Outbox](profiles/04_runtime/04_08_commit_outbox.md) | Business state and audit intent restore together; manual sink delivery can safely repeat. |
| `04_09_agent_observation` | [Agent Observation](profiles/04_runtime/04_09_agent_observation.md) | SDK events expose lifecycle, Turn, commit, and terminal outcomes. |
| `04_10_causal_trace` | [Causal Trace](profiles/04_runtime/04_10_causal_trace.md) | Child creation and work retain trace and cause identities across nodes. |
| `04_11_recoverable_delivery` | [Recoverable Delivery](profiles/04_runtime/04_11_recoverable_delivery.md) | A Plugin resumes committed delivery intent after loss. |
| `04_12_pending_job_recovery` | [Pending Job Recovery](profiles/04_runtime/04_12_pending_job_recovery.md) | Approval, attempt identity, retry, and cancellation survive restart. |
| `04_13_durable_scheduling` | [Durable Scheduling](profiles/04_runtime/04_13_durable_scheduling.md) | Saved occurrences retry until the result commit acknowledges them. |

## Multi-agent

| ID | Example | Added feature |
| --- | --- | --- |
| `05_01_child_lifecycle` | [Child Lifecycle](profiles/05_multi_agent/05_01_child_lifecycle.md) | A parent starts real children, tracks a restarted PID with the same ID, and stops owned processes. |
| `05_02_correlated_requests` | [Correlated Requests](profiles/05_multi_agent/05_02_correlated_requests.md) | Pending parent state, independent child work, and a later correlated reply form separate Turns. |
| `05_03_bounded_workers` | [Bounded Workers](profiles/05_multi_agent/05_03_bounded_workers.md) | At most eight live children reuse fixed slots; each result admits one queued item and results retain input order. |
| `05_04_agent_hierarchy` | [Agent Hierarchy](profiles/05_multi_agent/05_04_agent_hierarchy.md) | Each Agent owns direct children; branch loss is isolated and root shutdown removes the whole subtree. |
| `05_05_remote_child` | [Remote Child](profiles/05_multi_agent/05_05_remote_child.md) | A parent places and owns a child on a selected Erlang node. |
| `05_06_remote_lifecycle` | [Remote Lifecycle](profiles/05_multi_agent/05_06_remote_lifecycle.md) | Disconnect, node loss, parent loss, and replacement have explicit outcomes. |

See the [verification report](runtime-multi-agent-results.md) and [gap register](runtime-multi-agent-gaps.md).

## Factory

| ID | Example | Added feature |
| --- | --- | --- |
| `06_01_live_conversation` | [Live Conversation](profiles/06_factory/06_01_live_conversation.md) | Direct ReqLLM calls and Agent-owned text history. |
| `06_02_three_agent_system` | [Three-Agent System](profiles/06_factory/06_02_three_agent_system.md) | IEx chat, model tools, and feedback Signals during a model request. |
| `06_03_department_factory` | [Department Factory](profiles/06_factory/06_03_department_factory.md) | Four department heads execute a bounded dependency plan and return text artifacts. |
| `06_04_flow_factory` | [Flow Factory](profiles/06_factory/06_04_flow_factory.md) | A Flow coordinates nine workers with parallel builds, review Choice, and bounded repair. |

See the [run guide](../../lib/examples/06_factory/README.md) and
[orchestrator plan](../../lib/examples/06_factory/orchestrator-plan.md).
Factory tests use a local HTTP adapter. A live conversation succeeded with
`openai:gpt-4.1-mini`. The live workshop probe also passed for model tools,
scheduled work, worker cleanup, and feedback. Live department work remains unchecked.
See the [verification report](factory-results.md).
The [Flow factory report](flow-factory-results.md) covers its 14 tests and local
shell demos. Its live mode has local HTTP coverage; no live provider run was performed.
