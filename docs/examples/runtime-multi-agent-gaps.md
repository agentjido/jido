> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Runtime and Multi-agent gap register

Review date: **2026-09-04**. The initial review covered examples, tests, and
documentation. The approved [persistence follow-up](persistence-write-results.md)
adds atomic writes and Server revision checks. Other core work remains outside
this review.

The later [capability review](research-capabilities.md) defines 15 acceptance
targets and a real two-node diagnostic. Remote owned children are a core Jido
requirement. Vendor connectors do not define the next feature sequence.

A passing local fixture is evidence for its stated behavior only. A skipped
`flunk` placeholder records planned work. It does not prove that the SDK cannot
support that work. This register separates observed contract limits from
application policy, adapter work, scale work, and old fixture failures.

## First investigations

| ID | Owner | Evidence and consequence | Next experiment / decision |
| --- | --- | --- | --- |
| SDK-REMOTE (DIST-01 and DIST-02 resolved; DIST-03 paused) | Core Agent runtime | Placement and lifecycle proofs pass. DIST-03 proves cross-node restore and stale-revision fencing, then shows that both nodes can start the same logical Agent before another commit. | See [DIST-01](dist-01-results.md), [DIST-02](dist-02-results.md), and the [DIST-03 ownership decision](dist-03-results.md). No automatic failover or cluster singleton is claimed. |
| REC-01 resolved | Explicit Plugin capability | Eleven tests prove saved intent, restart, duplicate handling, completion, and known failed writes. | [REC-01 results](rec-01-results.md). Ordinary Directives are not replayed. Fresh-VM recovery and indeterminate-write authority remain outside this proof. |
| SDK-WRITE (resolved) | Persistence contract | Atomic compare-and-swap writes reject older revisions and concurrent updates. The State Recovery test is enabled. A rejected Server commit preserves live state and sends no Directives. | Custom adapters must implement `compare_and_swap/4`. File storage requires one BEAM owner. Distributed leases remain under SDK-CLUSTER. See the [persistence report](persistence-write-results.md). |
| PERSIST-01 | Core checkpoint validation | A valid record envelope can contain a different nested Agent ID. The loader returns that different Agent. | Reject the mismatch at load. Two controls pass and one enabled acceptance test fails. See [boundary probes](persistence-boundary-results.md). |
| PERSIST-02 | Core checkpoint validation | Load accepts a nested PID supplied by storage, although save rejects it. | Apply portable-data validation on load. Two controls pass and one enabled acceptance test fails. See [boundary probes](persistence-boundary-results.md). |
| PERSIST-03 | Core persistence admission | An adapter can store a write and return an unknown result. The live Server then evaluates another Action using stale state. | Define admission after an indeterminate result. Two controls pass and one enabled acceptance test fails. Database and VM lifecycle work are outside this probe. See [boundary probes](persistence-boundary-results.md). |
| SDK-SCHEDULE (REC-03 resolved for declared policy) | Explicit Scheduler delivery | Twenty-five tests pass: identity, saved intent, retry, completion, failed writes, cancellation, and generation checks. The original crash probe passes. | See the [REC-03 evidence](rec-03-results.md). One pending occurrence per job; busy and offline slots are skipped. External effects still require duplicate handling. Fresh-VM and distributed authority proofs remain separate. |
| REC-02 resolved | Application policy using Managed Jobs | Seven tests prove saved input and approval, fresh attempt IDs, cancellation, stale-result rejection, and recovery after Agent, Plugin, parent, and VM loss. | [REC-02 results](rec-02-results.md). Recovery is explicit retry or cancellation. Runtime handles are not persisted; external work still needs duplicate handling. |
| QA-GROUPS | Integration fixtures | The full suite still fails [Fixed Group](../../test/integration/fixed_group/fixed_group_test.exs) at its Bus replay wait and [Elastic Group](../../test/integration/elastic_group/elastic_group_test.exs) at its post-crash result wait. | Repair fixture scope first, then specify worker recovery. Re-run the complete scenarios without weakening their ownership, result, and cleanup assertions. |
| QA-HIBERNATE | Core runtime timing | The immediate hibernate/thaw instance test returns `already_started` because the previous PID is still registered. It fails both during node-targeting validation and in an isolated unchanged HEAD checkout. | Make successful hibernation confirm process exit and registry cleanup before immediate thaw. Preserve the current assertion. This is independent of remote placement. |
| QA-CONTEXT | Test timing investigation | During persistence validation, [ServerContextTest](../../test/jido/agent_server_context_test.exs) times out at its 100 ms delivery assertion in the concurrent full suite. It passes in focused and serial runs. The Agent has no persistence adapter. | Measure dispatch delay under concurrent test load and check shared test resources. Preserve the context and delivery assertions. See the [persistence report](persistence-write-results.md). |

The persistence probe uses public APIs:

```elixir
:ok = Jido.Persistence.save_agent(store, newer, revision: 2)
{:error, :conflict} = Jido.Persistence.save_agent(store, older, revision: 1)
{:ok, restored, 2} =
  Jido.Persistence.load_agent_with_revision(store, Counter, id)
```

`restored.state.count` is the newer value. Before the fix, both writes returned
`:ok` and revision 1 replaced revision 2. The enabled test now checks that the
newer record remains stored. Revision checks do not provide a writer lease
across deletion, expiry, or a new record lifetime.

## Group fixture diagnosis

The group tests create their Buses without a Jido instance. Their custom
[Bus input helper](../../test/support/integration_bus_input.ex) also uses global
lookup. Built-in [Directive dispatch](../../lib/jido/agent_server/directive_runtime.ex)
inherits the Agent's instance scope. These are different Bus namespaces.
The new Bus Delivery example consistently uses one instance and passes.

Fixed Group also expects a restarted worker to contain only the new task.
[Child Lifecycle](../../test/examples/05_multi_agent/05_01_child_lifecycle/child_lifecycle_test.exs)
now proves that restart retains the last committed child state and revision.
That old expectation needs an explicit fresh-worker policy.

Elastic Group commits `:busy` and a current task before scheduling a one-shot
finish Signal. It requeues work after a child exit, but a restored busy worker
can reject the new assignment. A one-shot timer is not a durable work lease.
This is the leading recovery explanation from source inspection; the full
scenario remains failing and was not patched in this review.

`SpawnAgent` rejects lifecycle options such as `restore` and `persistence`.
Do not add `restore: false` to its options as a fixture workaround. First choose
an application protocol for restart, attempt identity, and stale completion.

## Further design and implementation work

| ID | Owner | Current evidence | Next experiment / decision |
| --- | --- | --- | --- |
| SDK-OBSERVE (OBS-01 and OBS-02 resolved) | Core observation contract | OBS-01 has nine tests. OBS-02 has 12 tests for local/remote causation, startup, retry, failure, restore, and restart. | See the [OBS-02 evidence](obs-02-results.md). OBS-03 consumer and waiting-reason proof remains planned. |
| SDK-JOURNAL | Storage design | Commit Outbox stores business state and intent together. Event-Sourced Cart only folds local domain events. | Decide whether complete Agent snapshots meet the application need. If not, design atomic journal append and commit authority with a storage adapter. Test interrupted append and replay. |
| SDK-PLUGINS | Product and API design | Plugins declared in the Agent are static. The extension lifecycle sketch changes local manager data. | Decide whether live version replacement is required. If so, define state migration, in-flight work, rollback, resource ownership, and detach behavior before a core change. |
| SDK-CLUSTER (DIST-03) | Core identity and authority; advanced placement policy | Legacy cluster examples validate a supplied epoch in one process. No distributed lease or placement authority is tested. | Build on DIST-01 remote ownership. Test stable identity, stale activation rejection, and recovery authority on real nodes with shared storage. Sharding, rebalance, and singleton policy build on these guarantees. |
| APP-ORCHESTRATION | Application | The four new Multi-agent fixtures prove live children, correlation, bounded work, failure, and subtree cleanup. Most old team sketches only call functions or build lists. | Compose these features with domain policy. Add real handoff acknowledgement, review loops, or moderator selection only where independent Agent lifecycles are needed. |
| APP-ADAPTERS (CTRL-01, REC-01) | Core Plugin boundaries; provider protocol belongs in its integration package | Browser, MCP, A2A, Slack, sandbox, media, and external-agent fixtures use local adapters. A missing vendor Plugin does not establish a core gap. | Extract typed ingress, owned resources, reconnect, acknowledgement order, cancellation, cleanup, and recoverable output into provider-neutral tests. Live vendor integration is outside this package's capability ladder. |
| APP-SCALE | Application and performance QA | Agent Hierarchy tests seven live Agents. The old 120-worker and 1,500-Agent profiles create logical plans or reducers. | Build an opt-in load test with real Agents, bounded queues, monitored cleanup, latency, and memory measurements. Increase load only after failure cleanup is correct. |
| APP-OUTBOX | Application delivery policy | Duplicate commands are rejected; committed audit intent restores and repeated sink delivery is idempotent. | Define sink-wide record identity, acknowledgements, retry, retention, and a bounded drain. Inject a crash after a sink write and before acknowledgement. |

## Working policies and limits

- The keyed Timer Plugin is a working example extension. A built-in keyed
  Scheduler operation would reduce code; its absence is not a blocker.
- Correlated Requests and Bounded Workers select `:stop_on_error`, temporary
  children, and a one-second child execution deadline. Child failure becomes a
  lifecycle Signal. The default `:log_only` policy alone would not settle a
  waiting parent after an Action error.
- An ignored lifecycle event returns unchanged state and still advances the
  commit revision. Tests wait for child-start notifications before comparing
  revisions around rejected commands.
- A bounded request can contain many queued values, but at most eight child
  Agents are live. This is a concurrency bound, not an unbounded-ingress policy.
- Restarted Bus Client delivery may repeat a committed event. Bus Delivery
  returns success for that duplicate so the durable cursor can advance. Input
  Deduplication shows the separate policy of rejecting a duplicate command.
- Local ETS persistence and the in-memory Bus do not establish node-crash
  durability. DIST-01 now proves explicit remote child placement and ownership.
  Durable distributed recovery and authority remain unproved.

Every retained domain example maps to a current feature or capability target in the
[research assessment](runtime-multi-agent-research.md).
