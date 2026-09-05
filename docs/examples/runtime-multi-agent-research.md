> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Research ideas mapped to Jido capabilities

Review date: **2026-09-04**. This replaces the provider-oriented research queue.
The [capability ladder](research-capabilities.md) defines 12 targets in
observation, recovery, distributed Agents, and runtime control.

All 54 original profiles are accounted for below. Solved capabilities moved
into the main Runtime and Multi-agent groups. The 48 application and adapter
fixtures were removed from the runnable tree. Their profiles remain in the
archive, and their source remains in Git history at commit `bd05a32`.

**Covered** means the SDK question has an existing main feature example.
**Extract** means keep the useful requirement, remove the provider/domain
assumption, and implement the linked capability proof. This does not mean that
the target capability is implemented.

A Slack reply becomes stable input identity plus recoverable output delivery.
A browser or sandbox becomes an owned disposable resource. A team becomes
correlated live Agents and explicit work ownership. A cluster reducer becomes
a real two-node lifecycle and storage-authority test.

## Runtime ideas

| Original profile | Existing local evidence | Current target | Disposition |
| --- | --- | --- | --- |
| [04_01_burst_buncher](archive/runtime/04_01_burst_buncher.md) | An example Plugin replaces one keyed timer, ignores stale generations, and flushes one ordered batch. | [04_runtime/04_02_keyed_timers](profiles/04_runtime/04_02_keyed_timers.md) | Covered: Use the current keyed-timer fixture. |
| [04_02_scheduled_counter](archive/runtime/04_02_scheduled_counter.md) | A Scheduler Directive produces a later Signal and a separate commit. | [04_runtime/04_01_scheduled_signals](profiles/04_runtime/04_01_scheduled_signals.md) | Covered: Use the current scheduled-Signal fixture; durable occurrence recovery is REC-03. |
| [04_03_agent_live_debugger](archive/runtime/04_03_agent_live_debugger.md) | Public inspection exposes committed state and its matching revision while work is active. | [04_runtime/04_05_runtime_inspection](profiles/04_runtime/04_05_runtime_inspection.md) | Covered: Use the current inspection fixture; extend public observation through OBS-01. |
| [04_04_audit_outbox](archive/runtime/04_04_audit_outbox.md) | Business state and audit intent restore together; manual sink delivery can safely repeat. | [04_runtime/04_08_commit_outbox](profiles/04_runtime/04_08_commit_outbox.md) | Covered: Keep the manual outbox example; general committed effect recovery is REC-01. |
| [04_05_deduplicating_inbox](archive/runtime/04_05_deduplicating_inbox.md) | A stable input ID rejects duplicate work before a new commit; invalid input consumes no ID. | [04_runtime/04_07_input_deduplication](profiles/04_runtime/04_07_input_deduplication.md) | Covered: Use the current stable-input identity fixture. |
| [04_06_dynamic_tool_catalog](archive/runtime/04_06_dynamic_tool_catalog.md) | Provider selection and local tool calls | [03_llm/03_03_tool_call](profiles/03_llm/03_03_tool_call.md) | Covered: Provider discovery is not a separate core capability. Use typed tool calls. |
| [04_07_persistent_counter_recovery](archive/runtime/04_07_persistent_counter_recovery.md) | A restored Agent retains its complete state, duplicate ledger, and commit revision. | [04_runtime/04_06_state_recovery](profiles/04_runtime/04_06_state_recovery.md) | Covered: Use the current restore and stale-write tests. |
| [04_08_purpose_loop](archive/runtime/04_08_purpose_loop.md) | A finite purpose queue advances across Turns | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Recover pending work across Turns with an explicit attempt and restart policy. |
| [04_09_secure_signal_envelope](archive/runtime/04_09_secure_signal_envelope.md) | Fixture envelope encryption, decryption, and tamper rejection | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Test validated ingress and rejection before admission. Keep cryptographic wire formats in adapters. |
| [04_10_session_compaction_policy](archive/runtime/04_10_session_compaction_policy.md) | Local summary policy preserves complete history | [03_llm/03_08_context_compaction](profiles/03_llm/03_08_context_compaction.md) | Covered: Use Agent-owned history and explicit compaction; no separate provider project. |
| [04_11_session_replayed_task_board](archive/runtime/04_11_session_replayed_task_board.md) | A task projection rebuilds from saved entries | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Test restore of pending intent, definition mismatch, and invalid saved state. |
| [04_12_signed_signal_identity](archive/runtime/04_12_signed_signal_identity.md) | A local HMAC boundary rejects nonce replay | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Test trusted input normalization and duplicate identity. Adapter key management is outside the ladder. |
| [04_13_subscription_reconciliation](archive/runtime/04_13_subscription_reconciliation.md) | Set reconciliation in an Agent-based fake runtime | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Replace set arithmetic with a real input Plugin that rebuilds subscriptions from current state. |
| [04_14_automatic_trace_subscriber](archive/runtime/04_14_automatic_trace_subscriber.md) | An explicit wrapper exports a redacted top-level Turn | [OBS-01](profiles/04_runtime/04_09_agent_observation.md) | Extract: Observe actual SDK events, including failures and lifecycle changes, without command wrappers. |
| [04_15_background_job_supervisor](archive/runtime/04_15_background_job_supervisor.md) | A controlled GenServer sends later job results | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Lose the runtime after a job starts; reconcile persisted intent and reject old attempt results. |
| [04_16_browser_agent](archive/runtime/04_16_browser_agent.md) | Fixture browser plan validates origin and budget | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Use a neutral disposable resource to prove ownership, cancellation, and cleanup. Browser navigation is adapter work. |
| [04_17_code_sandbox_session](archive/runtime/04_17_code_sandbox_session.md) | A fixture returns a portable sandbox record | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Prove a resource lifetime and expiry contract. Sandbox implementation is adapter work. |
| [04_18_durable_schedule_recovery](archive/runtime/04_18_durable_schedule_recovery.md) | CRON state restores; supplied occurrence IDs deduplicate; generated templates lack an occurrence ID | [REC-03](profiles/04_runtime/04_13_durable_scheduling.md) | Extract: Create occurrence IDs in the runtime and test crash/redelivery with a controlled clock. |
| [04_19_embedded_agent_sdk](archive/runtime/04_19_embedded_agent_sdk.md) | An embedding facade returns typed terminal results | [OBS-03](../../lib/examples/99_research/99_01_progress_observation/README.md) | Extract: Prove subscription, progress, cancellation, and terminal-result behavior without a host product. |
| [04_20_event_sourced_cart](archive/runtime/04_20_event_sourced_cart.md) | A local domain-event fold reproduces a projection | [REC-01](profiles/04_runtime/04_11_recoverable_delivery.md) | Extract: First prove atomic state and effect intent. A domain-event journal remains a separate design choice. |
| [04_21_extension_package_lifecycle](archive/runtime/04_21_extension_package_lifecycle.md) | A local manager models versioned extension state | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Prove runtime replacement from committed state and cleanup. Choose configuration change policy before hot replacement. |
| [04_22_mcp_tool_client](archive/runtime/04_22_mcp_tool_client.md) | A fake MCP client validates approved discovered calls | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Test transport-neutral reconnect, typed input, and resource cleanup. MCP protocol support is adapter work. |
| [04_23_pdf_to_audio](archive/runtime/04_23_pdf_to_audio.md) | Fixture output covers the input section manifest | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Recover partial work and clean disposable artifacts using controlled operations. Media conversion is adapter work. |
| [04_24_slack_channel_agent](archive/runtime/04_24_slack_channel_agent.md) | A fake Slack boundary produces one threaded reply and deduplicates retries | [REC-01](profiles/04_runtime/04_11_recoverable_delivery.md) | Extract: Test stable input identity and recoverable post-commit delivery with a neutral sink; no Slack connection is required. |
| [04_25_streaming_chat](archive/runtime/04_25_streaming_chat.md) | Direct process messages deliver ordered partial text | [OBS-03](../../lib/examples/99_research/99_01_progress_observation/README.md) | Extract: Prove public progress and bounded slow-consumer behavior instead of direct process messages. |
| [04_26_tool_permission_gate](archive/runtime/04_26_tool_permission_gate.md) | Application policy allows, denies, or waits for tool approval | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Extend Workflow Approval with restore, expiry, cancellation, and stale decision tests. |
| [04_27_web_chat_ui](archive/runtime/04_27_web_chat_ui.md) | Transport-neutral session input restores state and deduplicates submits | [OBS-03](../../lib/examples/99_research/99_01_progress_observation/README.md) | Extract: Test consumer reconnect and result visibility; pair with REC-02 for durable waiting state. WebSocket UI is adapter work. |
| [04_28_causal_audit_tree](archive/runtime/04_28_causal_audit_tree.md) | Manual proof records and separate analysis relations validate locally | [OBS-02](profiles/04_runtime/04_10_causal_trace.md) | Extract: Derive causal records from real SDK events. Hand-built journals do not prove runtime trace capture. |
| [04_29_voice_assistant](archive/runtime/04_29_voice_assistant.md) | Semantic transcript events commit while raw frames stay in a fake runtime | [OBS-03](../../lib/examples/99_research/99_01_progress_observation/README.md) | Extract: Test bounded progress, interruption, and stale generations. Audio transport and synthesis are adapter work. |

## Multi-agent ideas

| Original profile | Existing local evidence | Current target | Disposition |
| --- | --- | --- | --- |
| [05_01_coordinator](archive/multi_agent/05_01_coordinator.md) | A single Agent correlates manually supplied reply and timeout events | [05_multi_agent/05_02_correlated_requests](profiles/05_multi_agent/05_02_correlated_requests.md) | Covered: Use real correlated child requests. |
| [05_02_sequential_specialist_team](archive/multi_agent/05_02_sequential_specialist_team.md) | Functions receive the previous specialist output in order | [02_workflow/02_01_sequential_flow](profiles/02_workflow/02_01_sequential_flow.md) | Covered: Use a Flow for one Turn; use child Agents only for separate lifecycles. |
| [05_03_concurrent_fanout_team](archive/multi_agent/05_03_concurrent_fanout_team.md) | Task-based fan-out joins in declared order | [05_multi_agent/05_03_bounded_workers](profiles/05_multi_agent/05_03_bounded_workers.md) | Covered: Use real bounded children, deadlines, and cleanup. |
| [05_04_fixed_group](archive/multi_agent/05_04_fixed_group.md) | Lists assign tasks to logical members | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Repair the real integration fixture and prove worker lifecycle and ownership; logical assignment lists are insufficient. |
| [05_05_group_chat](archive/multi_agent/05_05_group_chat.md) | Local functions follow a bounded speaker schedule | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Prove acknowledged control transfer between live Agents without a chat product. |
| [05_06_human_approval_gate](archive/multi_agent/05_06_human_approval_gate.md) | Two-Turn approval handles edits, rejection, expiry, and stale decisions | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Preserve approval intent across restart and settle each accepted decision once. |
| [05_07_research_team](archive/multi_agent/05_07_research_team.md) | Local reducers retain source ownership and validate citations | [03_llm/03_06_grounded_answer](profiles/03_llm/03_06_grounded_answer.md) | Covered: Compose grounding with Bounded Workers later; citation aggregation alone adds no runtime capability. |
| [05_08_round_robin_team](archive/multi_agent/05_08_round_robin_team.md) | Local participant functions run in fixed order | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Prove ordered live contributions and unavailable-participant handling. |
| [05_09_specialist_handoff](archive/multi_agent/05_09_specialist_handoff.md) | A state reducer validates owner transfer and reason | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Transfer ownership only after acknowledgement; handle unavailable recipients and duplicate replies. |
| [05_10_subagent_delegation](archive/multi_agent/05_10_subagent_delegation.md) | An adapter returns a summary without child history | [03_llm/03_09_subagent_delegation](profiles/03_llm/03_09_subagent_delegation.md) | Covered: Use the existing live child boundary and typed summary checks. |
| [05_11_supervisor_worker_team](archive/multi_agent/05_11_supervisor_worker_team.md) | Local assignment and review functions produce owned outputs | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Prove a bounded correction loop with real child failures and correlated results. |
| [05_12_support_email_agent](archive/multi_agent/05_12_support_email_agent.md) | Local classification, drafting, escalation, and idempotent delivery | [REC-01](profiles/04_runtime/04_11_recoverable_delivery.md) | Extract: Use neutral input, approval, and output to test delivery recovery; email transport is adapter work. |
| [05_13_swarm_handoffs](archive/multi_agent/05_13_swarm_handoffs.md) | Local peer functions transfer ownership within a bound | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Test live ownership transfer and stale acknowledgements. |
| [05_14_adaptive_swarm](archive/multi_agent/05_14_adaptive_swarm.md) | A reducer approves and rolls back policy versions | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Reconcile approved desired worker state after partial failure; measure the actual topology. |
| [05_15_agent_to_agent_protocol](archive/multi_agent/05_15_agent_to_agent_protocol.md) | A typed fixture remote event retains authentication and task correlation | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Test typed transport boundaries. External A2A protocol support is separate from Erlang remote child ownership. |
| [05_16_cluster_sharded_entities](archive/multi_agent/05_16_cluster_sharded_entities.md) | A local reducer checks a supplied ownership epoch | [DIST-03](../../lib/examples/99_research/99_02_distributed_authority/README.md) | Extract: Prove remote child placement first, then stable identity and stale activation rejection against authoritative storage. |
| [05_17_cluster_singleton](archive/multi_agent/05_17_cluster_singleton.md) | A local reducer rejects stale leader epochs | [DIST-03](../../lib/examples/99_research/99_02_distributed_authority/README.md) | Extract: Define ownership authority after remote lifecycle proofs. A local epoch comparison does not prove a distributed lease. |
| [05_18_codebase_review_tree](archive/multi_agent/05_18_codebase_review_tree.md) | Logical file ownership and finding reduction | [CTRL-03](../../lib/examples/99_research/99_05_capacity_deadlines_cleanup/README.md) | Extract: Build a real large Agent hierarchy and measure cleanup and bounds; file-review content is incidental. |
| [05_19_cross_framework_bridge](archive/multi_agent/05_19_cross_framework_bridge.md) | A terminal external adapter result validates before commit | [CTRL-01](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | Extract: Prove cancellation and lifecycle across a neutral external-work boundary; framework translation is adapter work. |
| [05_20_elastic_group](archive/multi_agent/05_20_elastic_group.md) | A reducer produces a bounded list of logical workers | [CTRL-02](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | Extract: Repair the integration recovery protocol and reconcile real worker processes under demand. |
| [05_21_medical_delegation](archive/multi_agent/05_21_medical_delegation.md) | Fixture evidence retains uncertainty and requires human review | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Use neutral review records to prove durable approval and ownership; domain/provider integration is outside this package. |
| [05_22_nested_cells](archive/multi_agent/05_22_nested_cells.md) | A logical topology validates ownership | [05_multi_agent/05_04_agent_hierarchy](profiles/05_multi_agent/05_04_agent_hierarchy.md) | Covered: Use current live ownership and branch isolation; larger-tree pressure belongs to CTRL-03. |
| [05_23_persistent_campaign](archive/multi_agent/05_23_persistent_campaign.md) | A reducer pauses and resumes finite campaign progress | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Persist pending requests, restore the parent, and reject old-generation child results. |
| [05_24_scripted_workflow_fanout](archive/multi_agent/05_24_scripted_workflow_fanout.md) | A local executor caches unchanged inputs and verifies results | [REC-02](profiles/04_runtime/04_12_pending_job_recovery.md) | Extract: Test durable work attempts and result reuse after failure; retain explicit application cache policy. |
| [05_25_swarm_control](archive/multi_agent/05_25_swarm_control.md) | Lists assign leases to 120 logical workers | [CTRL-03](../../lib/examples/99_research/99_05_capacity_deadlines_cleanup/README.md) | Extract: Start real workers and measure queue limits, deadline behavior, and complete cleanup. |

## Completion rules

- A capability needs one explicit behavior beyond the existing ladder.
- Core behavior must have a core test; the example must use the same supported API.
- Tests use real Agent Servers, Plugins, Directives, persistence, and peer nodes
  where that capability requires them. Test controls may hold work or cause failure.
- An adapter implementation, local state reducer, hand-built event journal, or
  list of logical workers cannot replace the corresponding runtime proof.
- Remote child creation must use Jido on the parent side. RPC may prepare the
  peer test environment, but an application RPC wrapper cannot satisfy DIST-01.
- No new skipped `flunk` placeholders are needed for these plans. Add the real
  acceptance test with the implementation, and keep observed gaps explicit.

See the [validation and priority report](research-capabilities.md), the
[gap register](runtime-multi-agent-gaps.md), and the
[historical profile archive](archive).
