> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Best-effort example implementation results

Run date: **2026-09-03** (original catalog pass).

> Historical results: Basic has since been rebuilt as five SDK integration
> fixtures with twenty passing tests and matching source folders. The ten
> old Basic sources were removed; their research profiles remain in the archive.
> See [current Basic results](basic-results.md). Counts below describe the
> original pass, not current SDK acceptance. Workflow has also been replaced by
> nine SDK fixtures; see [current Workflow results](workflow-results.md). LLM now
> has ten SDK fixtures; see [current LLM results](llm-results.md).

At that point, all **100 profiles** had an isolated source folder under `lib/examples`
and a matching test folder under `test/examples`. This pass added 68 source
examples. No file under `lib/jido` was changed.

The tests use only local fixtures, replay data, local processes, or local
cryptographic data. No live model, network, browser, cluster, media, or sandbox
service was used.

## Result meaning

- **implemented**: the local implementation and its current tests pass. This
  does not mean every listed failure case or live integration is covered.
- **doesn't work yet**: the basic spike runs, but the complete profile is not
  implemented. Each such profile has an explicit skipped contract test.
- **SDK contract**: a public runtime boundary needed by the profile is absent.
- **example scope**: the larger implementation was not built in this pass.
  This is not evidence that core Jido cannot support it.

Do not treat all skipped contracts as requests to add features to core Jido.
Many belong in an application adapter, a Plugin package, or a larger example.

| Group | Code and test folders | Implemented local scope | Doesn't work yet |
| --- | ---: | ---: | ---: |
| basic | 10 | 10 | 0 |
| workflow | 17 | 17 | 0 |
| llm | 19 | 18 | 1 |
| runtime | 29 | 15 | 14 |
| multi_agent | 25 | 4 | 21 |
| Total | 100 | 64 | 36 |

## Verification

- `mix test --only example`: 186 passed, 36 skipped, 566 excluded.
- `mix test`: 555 passed, 233 excluded.
- `mix compile --warnings-as-errors`: passed.
- Source format and diff checks: passed.
- Dialyzer: the same six existing core warnings remain; no example warning remains.
- Strict Credo: existing core, Basic, and Workflow findings remain; no new-example finding remains.

The normal suite emits existing type warnings in the SpanCtx, DeepMerge, and
ID tests. Strict Credo also reports existing core and test findings. Core files
were left unchanged.

## Important limits of these spikes

1. Most new LLM examples use one Action when a Flow does not add useful
   composition. The larger report examples sometimes consume a complete
   replay result. They are local contract tests, not production integrations.
2. Several multi-agent examples use functions, adapters, or Tasks as
   specialists. Their logical rules pass, but their full child Agent,
   correlation, deadline, and cleanup scenarios are marked incomplete.
3. The large tree and swarm examples test logical ownership and reducers.
   They do not claim to start 120 or 1,500 live Agents.
4. Some example adapters run effects before commit. Their local idempotency
   rules are explicit where writes are repeated. An Agent rollback does not
   undo an external effect.
5. The security examples use local fixtures. They are not a production
   security package. The signed-identity code uses shared-key HMAC; the older
   integration tests remain the reference for the Plugin admission path.
6. The approval gate stores plain pending work and uses a later Signal. It
   does not need a serialized Flow continuation.

## Review queue

These profiles are marked **doesn't work yet** in the catalog and their profile
files. Their basic local tests pass. The skipped test names state the remaining
contract.

| Group | Example | Gap type | Remaining contract |
| --- | --- | --- | --- |
| llm | [Deep Research](archive/llm/03_07_deep_research.md) | example scope | The replay adapter validates a finished research record. The full plan/search/fetch/revise loop and continuation are not implemented. |
| runtime | [Automatic Trace Subscriber](archive/runtime/04_14_automatic_trace_subscriber.md) | SDK contract | A complete read-only Signal, Turn, Flow, effect, Directive, retry, and shutdown event stream is missing. |
| runtime | [Background Job Supervisor](archive/runtime/04_15_background_job_supervisor.md) | example scope | The controlled GenServer proves later result Signals. Plugin-owned task supervision, durable delivery, and recovery are not implemented. |
| runtime | [Causal Audit Tree and Analysis Graph](archive/runtime/04_28_causal_audit_tree.md) | SDK contract | Manual proof data works. Automatic Action, Flow, child, effect, and Directive outcome capture is missing; the spike does not start child Agents. |
| runtime | [Code Sandbox Session](archive/runtime/04_17_code_sandbox_session.md) | example scope | The fixture validates an execution record. An isolated sandbox runtime with cancel, expiry, and cleanup is not implemented. |
| runtime | [Durable Schedule Recovery](archive/runtime/04_18_durable_schedule_recovery.md) | SDK contract | Schedule restore works. Stable logical occurrence identity and durable redelivery acknowledgement are missing. |
| runtime | [Embedded Agent SDK](archive/runtime/04_19_embedded_agent_sdk.md) | example scope | The facade proves typed prompt results. Stable subscriptions, steering, restore, cancellation, and cleanup are not implemented. |
| runtime | [Event-Sourced Cart](archive/runtime/04_20_event_sourced_cart.md) | SDK contract | The event fold works, but atomic domain-event journal append tied to Agent commit is missing. |
| runtime | [Extension Package Lifecycle](archive/runtime/04_21_extension_package_lifecycle.md) | SDK contract | The local manager validates lifecycle data. Live versioned capability install, reload, and removal are not public Agent runtime operations. |
| runtime | [MCP Tool Client](archive/runtime/04_22_mcp_tool_client.md) | example scope | Discovery and approved calls work through a fake adapter. Managed MCP transport, reconnect, notifications, and cancellation are not implemented. |
| runtime | [PDF to Audio](archive/runtime/04_23_pdf_to_audio.md) | example scope | The fixture validates complete manifest coverage. Extraction, synthesis, artifact ownership, and partial-output cleanup are not implemented. |
| runtime | [Persistent Counter Recovery](archive/runtime/04_07_persistent_counter_recovery.md) | Resolved | The later [persistence fix](persistence-write-results.md) adds atomic compare-and-swap writes and enables the stale-writer test. |
| runtime | [Streaming Chat](archive/runtime/04_25_streaming_chat.md) | SDK contract | Direct process messages prove ordered progress. A stable active-Turn progress channel with backpressure is missing. |
| runtime | [Realtime Voice Assistant](archive/runtime/04_29_voice_assistant.md) | example scope | Semantic transcript events work. A supervised realtime media connection with backpressure and cleanup is not implemented. |
| runtime | [Web Chat UI](archive/runtime/04_27_web_chat_ui.md) | example scope | The transport-neutral session restores state and rejects duplicate submits. WebSocket input, authentication, and progress delivery are not implemented. |
| multi_agent | [Adaptive Swarm](archive/multi_agent/05_14_adaptive_swarm.md) | example scope | Policy proposal, approval, and rollback state work. Experiments and live topology rollback are not implemented. |
| multi_agent | [Agent-to-Agent Protocol](archive/multi_agent/05_15_agent_to_agent_protocol.md) | example scope | The typed remote-event reducer works. A2A discovery, transport, authentication, reconnect, and cancellation are not implemented. |
| multi_agent | [Cluster-Sharded Entities](archive/multi_agent/05_16_cluster_sharded_entities.md) | SDK contract | Local epoch validation works. Distributed routing, placement, rebalance, passivation, and authoritative fencing are missing. |
| multi_agent | [Cluster Singleton](archive/multi_agent/05_17_cluster_singleton.md) | SDK contract | Local leader-epoch validation works. Cluster placement, leases, failover, and distributed fencing are missing. |
| multi_agent | [Codebase Review Tree](archive/multi_agent/05_18_codebase_review_tree.md) | example scope | Logical file ownership and finding reduction work. The approximately 1,500-Agent tree and cleanup scenario are not implemented. |
| multi_agent | [Concurrent Fan-Out Team](archive/multi_agent/05_03_concurrent_fanout_team.md) | example scope | Task-based concurrent join order works. Supervised child Agent delivery, deadline handling, and cleanup are not implemented. |
| multi_agent | [Cross-Framework Bridge](archive/multi_agent/05_19_cross_framework_bridge.md) | example scope | The terminal adapter result is validated. Managed remote progress, cancellation, reconnect, and cleanup are not implemented. |
| multi_agent | [Moderated Group Chat](archive/multi_agent/05_05_group_chat.md) | example scope | A bounded moderator and local participants work. Separate child reply Signals, timeout, and participant lifecycle are not implemented. |
| multi_agent | [Medical Agent Delegation](archive/multi_agent/05_21_medical_delegation.md) | example scope | De-identified evidence, uncertainty, and human ownership work. Durable approval, secure transport, and controlled clinical integrations are not implemented. |
| multi_agent | [Nested Agent Cells](archive/multi_agent/05_22_nested_cells.md) | example scope | Logical hierarchy and unique worker ownership work. Real nested Agent failure isolation and complete tree stop are not implemented. |
| multi_agent | [Persistent Campaign](archive/multi_agent/05_23_persistent_campaign.md) | example scope | Finite pause, resume, and task-result state work. Persistence recovery, temporary child ownership, and cleanup are not implemented. |
| multi_agent | [Research Team](archive/multi_agent/05_07_research_team.md) | example scope | Source ownership, deduplication, and citations work. Parallel child Agents, deadlines, and cleanup are not implemented. |
| multi_agent | [Round-Robin Agent Team](archive/multi_agent/05_08_round_robin_team.md) | example scope | Bounded participant order works. Separate child contribution Signals and timeout handling are not implemented. |
| multi_agent | [Scripted Workflow Fan-Out](archive/multi_agent/05_24_scripted_workflow_fanout.md) | example scope | Input-digest caching and verification work. Bounded child Agent concurrency, durable restart, and orphan cleanup are not implemented. |
| multi_agent | [Sequential Specialist Team](archive/multi_agent/05_02_sequential_specialist_team.md) | example scope | Ordered specialist transformations work. Separate child Agent Turns, correlated replies, and lifecycle cleanup are not implemented. |
| multi_agent | [Specialist Handoff](archive/multi_agent/05_09_specialist_handoff.md) | example scope | Active-owner transfer and reason checks work. Post-commit child delivery and unavailable-child handling are not implemented. |
| multi_agent | [Subagent Delegation](archive/multi_agent/05_10_subagent_delegation.md) | example scope | An isolated adapter returns only a typed summary. Spawn, reply correlation, deadline, and child cleanup are not implemented. |
| multi_agent | [Supervisor and Worker Team](archive/multi_agent/05_11_supervisor_worker_team.md) | example scope | Assignment ownership and review work. Child Agent dispatch, correction loops, deadlines, and cleanup are not implemented. |
| multi_agent | [Support Email Agent](archive/multi_agent/05_12_support_email_agent.md) | example scope | Classification, drafting, escalation, and idempotent writes work. Input Plugin delivery, post-commit dispatch, and scheduled follow-up are not implemented. |
| multi_agent | [Swarm Control](archive/multi_agent/05_25_swarm_control.md) | example scope | A 120-worker logical partition plan works. Live Agent scale, failure, backpressure, and complete process/subscription cleanup are not implemented. |
| multi_agent | [Swarm Handoffs](archive/multi_agent/05_13_swarm_handoffs.md) | example scope | Bounded peer decisions and final ownership work. Live peer Agent delivery, lifecycle, and failure handling are not implemented. |

## Implemented local examples

### basic

- [Bounded Counter](archive/basic/bounded-counter.md)
- [Calculator Action](archive/basic/calculator-action.md)
- [Typed Command Router](archive/basic/command-router.md)
- [Conversation Thread](archive/basic/conversation-thread.md)
- [Counter](archive/basic/counter.md)
- [Retry Budget](archive/basic/retry-budget.md)
- [Round-Robin Local Router](archive/basic/round-robin-local-router.md)
- [Task List](archive/basic/todo-list.md)
- [Toggle State Machine](archive/basic/toggle-state-machine.md)
- [Typed Profile Update](archive/basic/typed-profile-update.md)

### workflow

- [Conditional Fallback](archive/workflow/02_01_conditional_fallback.md)
- [Effectful Weather Lookup](archive/workflow/02_02_effectful_weather_lookup.md)
- [Customer Feedback Summarizer](archive/workflow/02_03_feedback_summarizer.md)
- [Flight Booking Assistant](archive/workflow/02_17_flight_booking.md)
- [Hybrid Search](archive/workflow/02_04_hybrid_search.md)
- [Lead Qualification](archive/workflow/02_05_lead_qualification.md)
- [Learning Guide Creator](archive/workflow/02_06_learning_guide_creator.md)
- [Metadata-Filtered Search](archive/workflow/02_07_metadata_filtered_search.md)
- [Mixed File Ingestion](archive/workflow/02_08_mixed_file_ingestion.md)
- [PDF Flash Cards](archive/workflow/02_09_pdf_flash_cards.md)
- [Safe SQL Assistant](archive/workflow/02_10_safe_sql_assistant.md)
- [Sequential Data Flow](archive/workflow/02_11_sequential_data_flow.md)
- [Spreadsheet Analysis](archive/workflow/02_12_spreadsheet_analysis.md)
- [Structured Output Repair](archive/workflow/02_13_structured_output_repair.md)
- [Trip Itinerary](archive/workflow/02_14_trip_itinerary.md)
- [Typed Bank Support](archive/workflow/02_15_typed_bank_support.md)
- [Writer and Editor](archive/workflow/02_16_writer_editor.md)

### llm

- [Agentic RAG](archive/llm/03_01_agentic_rag.md)
- [Coding Assistant](archive/llm/03_02_coding_assistant.md)
- [Company Research Report](archive/llm/03_03_company_research.md)
- [Conversation Summarization](archive/llm/03_04_conversation_summarization.md)
- [Conversational RAG with Memory](archive/llm/03_05_conversational_rag_memory.md)
- [Data Analyst](archive/llm/03_06_data_analyst.md)
- [Document Question Answering](archive/llm/03_08_document_question_answering.md)
- [Literature Review](archive/llm/03_09_literature_review.md)
- [Marketing Strategy](archive/llm/03_10_marketing_strategy.md)
- [Model Fallback](archive/llm/03_11_model_fallback.md)
- [Multimodal Document Agent](archive/llm/03_12_multimodal_document_agent.md)
- [Plan and Execute](archive/llm/03_13_plan_and_execute.md)
- [RAG with Web Fallback](archive/llm/03_14_rag_web_fallback.md)
- [ReAct Agent](archive/llm/03_15_react_agent.md)
- [Self-Evaluation Loop](archive/llm/03_16_self_evaluation_loop.md)
- [Single-Tool Agent](archive/llm/03_17_single_tool_agent.md)
- [Starter Chatbot](archive/llm/03_18_starter_chatbot.md)
- [Stock Analysis Report](archive/llm/03_19_stock_analysis.md)

### runtime

- [Agent Live Debugger](archive/runtime/04_03_agent_live_debugger.md)
- [Audit Outbox](archive/runtime/04_04_audit_outbox.md)
- [Browser Agent](archive/runtime/04_16_browser_agent.md)
- [Burst Buncher](archive/runtime/04_01_burst_buncher.md)
- [Deduplicating Inbox](archive/runtime/04_05_deduplicating_inbox.md)
- [Dynamic Tool Catalog](archive/runtime/04_06_dynamic_tool_catalog.md)
- [Finite Purpose Loop](archive/runtime/04_08_purpose_loop.md)
- [Scheduled Counter](archive/runtime/04_02_scheduled_counter.md)
- [Secure Signal Envelope](archive/runtime/04_09_secure_signal_envelope.md)
- [Session Compaction Policy](archive/runtime/04_10_session_compaction_policy.md)
- [Session-Replayed Task Board](archive/runtime/04_11_session_replayed_task_board.md)
- [Signed Signal Identity](archive/runtime/04_12_signed_signal_identity.md)
- [Slack Channel Agent](archive/runtime/04_24_slack_channel_agent.md)
- [Subscription Reconciliation](archive/runtime/04_13_subscription_reconciliation.md)
- [Tool Permission Gate](archive/runtime/04_26_tool_permission_gate.md)

### multi_agent

- [Coordinator and Worker](archive/multi_agent/05_01_coordinator.md)
- [Elastic Agent Group](archive/multi_agent/05_20_elastic_group.md)
- [Fixed Agent Group](archive/multi_agent/05_04_fixed_group.md)
- [Human Approval Gate](archive/multi_agent/05_06_human_approval_gate.md)

## How to run

Run the opt-in suite:

```shell
mix test --only example
```

Run one group:

```shell
mix test --include example test/examples/03_llm
```

Historical source and tests remain available at commit `bd05a32`. They are not
part of the runnable example tree.

The ordinary `mix test` command excludes the example suite. Tests tagged
`:skip` remain visible as incomplete contracts. Remove a skip only when the
stated full-profile behavior has an actual implementation and assertion.
