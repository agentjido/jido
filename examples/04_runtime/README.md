# Runtime feature examples

This sequence has 13 source fixtures. The first eight have 29 opt-in example
tests. The five promoted capability examples have 64 core acceptance tests.
All 93 tests pass with no skips.

| Order | Added feature | Tests |
| --- | --- | ---: |
| [04_01_scheduled_signals](04_01_scheduled_signals/scheduled_counter.ex) | A Scheduler Directive produces a later Signal and a separate commit. | 3 example |
| [04_02_keyed_timers](04_02_keyed_timers/burst_buncher.ex) | A Plugin replaces one keyed timer and ignores stale generations. | 4 example |
| [04_03_bus_delivery](04_03_bus_delivery/bus_delivery.ex) | A Bus Client retries failed Turns and acknowledges after commit. | 4 example |
| [04_04_managed_jobs](04_04_managed_jobs/managed_jobs.ex) | An Agent-owned Plugin starts linked work after commit. | 6 example |
| [04_05_runtime_inspection](04_05_runtime_inspection/agent_live_debugger.ex) | Inspection reports committed state and revision during active work. | 2 example |
| [04_06_state_recovery](04_06_state_recovery/persistent_counter_recovery.ex) | Restore retains state, duplicate ledger, and revision. | 5 example |
| [04_07_input_deduplication](04_07_input_deduplication/deduplicating_inbox.ex) | A stable input ID rejects duplicate work before commit. | 2 example |
| [04_08_commit_outbox](04_08_commit_outbox/audit_outbox.ex) | Business state and audit intent restore together. | 3 example |
| [04_09_agent_observation](04_09_agent_observation/turn_observation.ex) | SDK events expose lifecycle, Turn, commit, and terminal outcomes. | 9 core |
| [04_10_causal_trace](04_10_causal_trace/causal_trace.ex) | Local and remote child work retains explicit creation causes. | 12 core |
| [04_11_recoverable_delivery](04_11_recoverable_delivery/recoverable_delivery.ex) | A Plugin resumes committed output intent after loss. | 11 core |
| [04_12_pending_job_recovery](04_12_pending_job_recovery/pending_job_recovery.ex) | Approval, attempt identity, retry, and cancellation survive restart. | 7 core |
| [04_13_durable_scheduling](04_13_durable_scheduling/scheduled_occurrence_recovery.ex) | Saved schedule occurrences retry until the result commit acknowledges them. | 25 core |

Run the opt-in example tests:

```shell
mix test --include example test/examples/04_runtime --seed 0
```

Each promoted profile links its focused core command. See the
[Runtime profiles](../../docs/examples/catalog.md#runtime) and the
[research queue](../99_research/README.md).
