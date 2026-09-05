# Example transfer register

Status: core transfer planned. Prepared source: `jido_v3@bf6c9fb`.
No examples have been transferred into core.

All 52 fixtures are required. Copy their prepared implementation, assertions,
profiles, and support. Naming and confirmed source repairs are complete.
Record any further core-specific change. The manifest retains original Actor
paths and baseline results separately from the current Agent paths and results.

The current full run at `bf6c9fb` passed 1005 tests with zero failures and
one user-approved skip: DIST-03 cluster ownership. All catalog and application
scenario selections pass. The table uses this current per-test record.
These are donor results, not core migration results.

## Catalog

| Prepared source and core ID | Commit | Source tests | Source result | Contract and exact paths |
| --- | --- | ---: | --- | --- |
| `01_01_minimal_agent` | M02 | 3 | Pass | [Direct/live agreement and instance isolation.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/01_basic/01_01_minimal_agent.md) |
| `01_02_typed_command_agent` | M02 | 4 | Pass | [Construction, route selection, input validation, and complete candidate validation.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/01_basic/01_02_typed_command_agent.md) |
| `01_03_plugin_state_agent` | M02 | 3 | Pass | [Plugin state ownership and atomic domain/Plugin commit.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/01_basic/01_03_plugin_state_agent.md) |
| `01_04_directive_agent` | M02 | 3 | Pass | [Whole-batch validation and ordered post-commit dispatch.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/01_basic/01_04_directive_agent.md) |
| `01_05_controlled_turn_agent` | M02 | 3 | Pass | [Turn serialization, cancellation, queued work, and caller timeout.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/01_basic/01_05_controlled_turn_agent.md) |
| `02_01_sequential_flow` | M05 | 4 | Pass | [Input and output schemas, result dependencies, control dependencies, and one complete commit.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_01_sequential_flow.md) |
| `02_02_effectful_steps` | M05 | 3 | Pass | [Transient caller context, effect guards, explicit output projection, idempotency, and persistence.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_02_effectful_steps.md) |
| `02_03_conditional_routes` | M05 | 3 | Pass | [First-match Choice, lazy branch work, explicit failure capture, and selected-Action errors.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_03_conditional_routes.md) |
| `02_04_parallel_join` | M05 | 5 | Pass | [Concurrent independent steps, join dependencies, execution limits, failure, and cancellation.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_04_parallel_join.md) |
| `02_05_ordered_batch` | M05 | 4 | Pass | [Ordered Map results, collected errors, fail-fast commit behavior, empty input, and serial Reduce.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_05_ordered_batch.md) |
| `02_06_bounded_iteration` | M05 | 3 | Pass | [Initial completion, exact loop bounds, and validation of initial and replacement state.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_06_bounded_iteration.md) |
| `02_07_nested_flow` | M05 | 4 | Pass | [Separate child result scopes, shared context, child schemas, typed failures, and shared timeout.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_07_nested_flow.md) |
| `02_08_executable_continuation` | M05 | 4 | Pass | [Dispatch, shared context and continuation budget, terminal output validation, and timeout.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_08_executable_continuation.md) |
| `02_09_approval_workflow` | M05 | 5 | Pass | [Separate approval Turns, post-commit Plugin dispatch, correlation, duplicates, and provider failure.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/02_workflow/02_09_approval_workflow.md) |
| `03_01_model_response` | M06 | 4 | Pass | [One typed response, transient client context, selected persisted fields, and explicit fallback policy.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_01_model_response.md) |
| `03_02_conversation_history` | M06 | 2 | Pass | [Actual history across Turns, duplicate rejection, and restore with a fresh client.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_02_conversation_history.md) |
| `03_03_tool_call` | M06 | 4 | Pass | [An approved name resolves to a typed Action; invalid input stops before tool effects.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_03_tool_call.md) |
| `03_04_tool_loop` | M06 | 11 | Pass | [Flow Dispatch and continuation carry model/tool rounds to one terminal commit.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_04_tool_loop.md) |
| `03_05_parallel_tools` | M06 | 5 | Pass | [Validate a complete tool plan, run concurrent Actions with Map, and retain call-ID order.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_05_parallel_tools.md) |
| `03_06_grounded_answer` | M06 | 3 | Pass | [Retrieve evidence, generate an answer, and validate citation identity, revision, and page before commit.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_06_grounded_answer.md) |
| `03_07_output_repair` | M06 | 3 | Pass | [Flow Iterate carries validation feedback through at most three model attempts.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_07_output_repair.md) |
| `03_08_context_compaction` | M06 | 2 | Pass | [Compact committed history and retain recent and queued messages under an explicit byte limit.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_08_context_compaction.md) |
| `03_09_subagent_delegation` | M06 | 6 | Pass | [Spawn a real child Agent, transfer client context explicitly, and correlate result and failure Signals.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_09_subagent_delegation.md) |
| `03_10_recursive_analysis` | M06 | 26 | Pass | [This example tests execution and data boundaries. Model decisions are scripted. It does not measure model reasoning quality or execute model-generated code. The single supported query is `:failed_jobs_by_service`.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/03_llm/03_10_recursive_analysis.md) |
| `04_01_scheduled_signals` | M07 | 3 | Pass | [A Scheduler Directive produces a later Signal and a separate commit. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_01_scheduled_signals.md) |
| `04_02_keyed_timers` | M07 | 4 | Pass | [An example Plugin replaces one keyed timer, ignores stale generations, and flushes one ordered batch. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_02_keyed_timers.md) |
| `04_03_bus_delivery` | M07 | 4 | Pass | [A real Bus Client delivers ordered records, retries failed Turns, and acknowledges after commit. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_03_bus_delivery.md) |
| `04_04_managed_jobs` | M07 | 6 | Pass | [An Agent-owned Plugin starts a linked task after commit and sends a later terminal Signal. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_04_managed_jobs.md) |
| `04_05_runtime_inspection` | M07 | 2 | Pass | [Public inspection exposes committed state and its matching revision while work is active. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_05_runtime_inspection.md) |
| `04_06_state_recovery` | M07 | 5 | Pass | [A restored Agent retains its complete state, duplicate ledger, and commit revision. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_06_state_recovery.md) |
| `04_07_input_deduplication` | M07 | 2 | Pass | [A stable input ID rejects duplicate work before a new commit; invalid input consumes no ID. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_07_input_deduplication.md) |
| `04_08_commit_outbox` | M07 | 3 | Pass | [Business state and audit intent restore together; manual sink delivery can safely repeat. Read this after the Basic and Workflow groups.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_08_commit_outbox.md) |
| `04_09_agent_observation` | M07 | 9 | Pass | [SDK telemetry reports Agent lifecycle, Turn settlement, commits, and Directive outcomes without command wrappers or application-generated events.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_09_agent_observation.md) |
| `04_10_causal_trace` | M07 | 12 | Pass | [Child creation, work, results, retries, restore, and restart retain explicit trace and cause identities across local and remote Agent Turns.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_10_causal_trace.md) |
| `04_11_recoverable_delivery` | M07 | 11 | Pass | [Business state and delivery intent commit together. A supervised Plugin resumes pending output after Agent or Plugin loss and confirms completion in a new Turn.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_11_recoverable_delivery.md) |
| `04_12_pending_job_recovery` | M07 | 7 | Pass | [Saved input, approval, attempt identity, retry, cancellation, and stale-result rejection recover after Agent, Plugin, parent, or VM loss.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_12_pending_job_recovery.md) |
| `04_13_durable_scheduling` | M07 | 26 | Pass | [The Scheduler saves one logical occurrence before delivery and removes it only when the business result commits. Generation and occurrence identity reject stale or duplicate work.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/04_runtime/04_13_durable_scheduling.md) |
| `05_01_child_lifecycle` | M08 | 3 | Pass | [A parent starts real children, tracks a restarted PID with the same ID, and stops owned processes. Read this after the Runtime group and the previous Multi-agent example.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/05_multi_agent/05_01_child_lifecycle.md) |
| `05_02_correlated_requests` | M08 | 6 | Pass | [Pending parent state, independent child work, and a later correlated reply form separate Turns. Read this after the Runtime group and the previous Multi-agent example.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/05_multi_agent/05_02_correlated_requests.md) |
| `05_03_bounded_workers` | M08 | 5 | Pass | [At most eight live children reuse fixed slots; each result admits one queued item and results retain input order. Read this after the Runtime group and the previous Multi-agent example.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/05_multi_agent/05_03_bounded_workers.md) |
| `05_04_agent_hierarchy` | M08 | 4 | Pass | [Each Agent owns direct children; branch loss is isolated and root shutdown removes the whole subtree. Read this after the Runtime group and the previous Multi-agent example.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/05_multi_agent/05_04_agent_hierarchy.md) |
| `05_05_remote_child` | M08 | 16 | Pass | [A parent places and owns a child Agent on a selected Erlang node. Signals, restart, stop, parent loss, delayed creation, and request identity use the same Agent contract across nodes.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/05_multi_agent/05_05_remote_child.md) |
| `05_06_remote_lifecycle` | M08 | 4 | Pass | [A parent distinguishes a confirmed remote process exit from an unreachable node, stops remote work after parent loss, and requires explicit replacement after reconnect.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/05_multi_agent/05_06_remote_lifecycle.md) |
| `06_01_live_conversation` | M09 | 4 | Pass | [One Agent calls ReqLLM and stores text history. Local HTTP tests check request encoding, response decoding, duplicates, and error isolation. Interactive provider use is separate.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/06_factory/06_01_live_conversation.md) |
| `06_02_three_agent_system` | M09 | 26 | Pass | [A System Agent owns conversation and factory Agents. Tests prove FIFO jobs, one active worker, controls, retries, stale progress rejection, streaming, batch idempotency, and shutdown.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/06_factory/06_02_three_agent_system.md) |
| `06_03_department_factory` | M09 | 4 | Pass | [Research, Design, Build, and Quality Agents follow a fixed dependency plan with at most two active steps. Tests check result identity, pause, cancellation, failure, and shutdown.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/06_factory/06_03_department_factory.md) |
| `06_04_flow_factory` | M09 | 14 | Pass | [A Mission Agent owns nine department Agents. The real Flow proves parallel joins, ordered Map, Choice, two repairs, and handoff of the accepted revision.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/06_factory/06_04_flow_factory.md) |
| `07_01_independent` | M10 | 1 | Pass | [Two Agents start from one static topology. Their state and lifecycle are independent.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/07_topology/07_01_independent.md) |
| `07_02_hierarchy` | M10 | 1 | Pass | [A coordinator owns one leader. The leader owns three workers. All processes remain in the Jido Agent pool.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/07_topology/07_02_hierarchy.md) |
| `07_03_bus_swarm` | M10 | 1 | Pass | [A stored JSON definition starts 1000 workers and one coordinator. One Bus Signal reaches every worker. The test sets Jido task capacity to 4096.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/07_topology/07_03_bus_swarm.md) |
| `07_04_keyed_accounts` | M10 | 1 | Pass | [Account records supply stable group member keys and initial labels. Reordering the records does not change Agent identity.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/07_topology/07_04_keyed_accounts.md) |
| `07_05_composed_system` | M10 | 1 | Pass | [Two copies of a reusable team use separate inputs and stable identities. One root-owned Bus supplies both teams. Public exports provide access to leaders, workers, and the shared Bus. The root director owns the two leaders; each leader owns its workers. DSL, Builder, and JSON forms produce the same plan.](/Users/mhostetler/.codex/worktrees/0d9b/jido_v3/docs/examples/profiles/07_topology/07_05_composed_system.md) |

The catalog has 302 direct executions plus 15 shared checks: 317 passed.
The application scenarios have 13 passing tests. Topology core adds 47.
Counts are executed tests in the source run, not source-code `test` declarations.
Some files generate multiple tests. Shared group tests are listed separately.

## Shared checks and source

| Group | Shared tests executed | Shared test files |
| --- | ---: | --- |
| 01_basic | 6 | `test/examples/01_basic/authoring_formats_test.exs` |
| 06_factory | 9 | `test/examples/06_factory/streaming_test.exs` |

Also transfer each group-level source file and its required `test/support`
modules from the manifest. In particular, LLM Adapter, workflow observations,
Factory protocol/tools/model/inspection helpers and HTTP/SSE fixtures are part
of the runnable examples. Topology adds all four `test/jido/topology` test files.

Seven catalog fixtures store their acceptance tests outside their own folders:
04_09–04_13 and 05_05–05_06. Their exact core paths are in the manifest.
A test-location README is not a passing test.

## Application scenarios

These 10 scenarios are additional to the catalog. Transfer both implementation
fixtures and test files. Preserve identity/encryption/replay checks and recovery
assertions. Run every scenario before the migration closes.

| Scenario | Commit | Source tests executed | Source result |
| --- | --- | ---: | --- |
| `audit` | M11 | 1 | Pass |
| `coordinator` | M11 | 1 | Pass |
| `elastic_group` | M11 | 2 | Pass |
| `fixed_group` | M11 | 1 | Pass |
| `identity` | M11 | 1 | Pass |
| `inbox` | M11 | 1 | Pass |
| `purpose_loop` | M11 | 2 | Pass |
| `react` | M11 | 2 | Pass |
| `secure_signal` | M11 | 1 | Pass |
| `subscription` | M11 | 1 | Pass |

## Research

| Source folder | Executed source tests | Source result | Core disposition |
| --- | ---: | --- | --- |
| `99_01_progress_observation` | 0 | No executable test | design backlog |
| `99_02_distributed_authority` | 1 | 1 pass; DIST-03 skipped by user request | M11: retain explicit exception |
| `99_03_input_resource_lifecycle` | 0 | No executable test | design backlog |
| `99_04_handoff_reconciliation` | 0 | No executable test | design backlog |
| `99_05_capacity_deadlines_cleanup` | 0 | No executable test | design backlog |
| `99_06_checkpoint_identity` | 3 | Pass | M03 |
| `99_07_checkpoint_portability` | 3 | Pass | M03 |
| `99_08_indeterminate_write` | 4 | Pass | M03 |

The three persistence probes are required correctness checks, even though they
carry research metadata. The four narrative-only research folders do not add
passing tests to the total. DIST-03 is the one approved skip. Cluster ownership
remains unimplemented. Keep its evidence and assertion visible. A required failing test cannot be hidden by a general
`--exclude research` option.

## Transfer rules

1. Export from the pinned Git revision, not from an evolving donor checkout.
2. Copy the prepared Agent names and formats. Do not repeat the Actor rename.
3. Preserve domain data, control barriers, assertion strength, ordering, retry
   bounds, budgets, errors, model fixtures and cleanup expectations.
4. Compare each target to the prepared source. Record any remaining change
   with its reason, owning commit and supporting regression test.
5. Run the exact mapped test set. Fail if a listed path is missing or selects
   zero tests. Include shared checks and supporting core test files.
6. Record core revision, runtime, seed, test count, result and log. Mark a fixture
   migrated only after that core run passes.

The archived application sketches remain historical design material. Do not
restore or count all archive entries as implemented examples. Numeric catalog
identity stays stable when a descriptive Actor path becomes an Agent path.

The profile links open the prepared worktree. The original sibling remains Actor-based.
The immutable revisions and paths in sources.json remain the portable source
record when the sibling repository is not present.
