> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Runtime timing and recovery burn-in results

> The Runtime and Multi-agent catalog was reorganized on 2026-09-04. See the
> [current feature review](runtime-multi-agent-results.md) for current paths, test
> totals, and gap ownership. Results below describe the earlier review.

Run date: **2026-09-03**.

This report covers Wave 1 Group C. The examples use only local processes,
controlled triggers, scripted model responses, and isolated ETS state. No file
under `lib/jido` changed to make an example pass.

| Example | Result | Main contract tested |
| --- | --- | --- |
| Burst Buncher | passed | Keyed timer replacement, ordered batch flush, and duplicate item rejection |
| Persistent Counter Recovery | failed burn-in | Restore and duplicate handling pass; stale-writer rejection has no persistence contract |
| ReAct failure matrix | passed | Multiple tools, bounded continuation, failures, timeout, and cancellation |
| Durable Schedule Recovery | failed burn-in | Schedule restore and domain deduplication pass; stable runtime occurrence identity is missing |

The group has 23 passing tests and 2 explicitly skipped contract tests.

## Developer model that worked

1. Agent state owns batching, deduplication, generation, and retry policy.
2. One Signal starts one finite Action or Flow Turn.
3. A real OTP capability owns timers or recurring runtime work.
4. Stable command and occurrence IDs belong in application-visible data.
5. Persistence restores complete Agent and Plugin state before runtime work
   restarts.
6. A successful terminal result commits once. A failure commits nothing.

The ReAct example confirms that recursive tool use does not require a
long-lived Flow. A finite counter in Flow input bounds the work. Agent Server
cancellation can stop the complete active Turn.

## SDK friction and simplification opportunities

### 1. Persistent writes have no compare-and-swap contract

The public persistence adapter has byte `get`, `put`, and `delete` callbacks.
It cannot receive expected write authority or return a new storage token. A
stale Server can overwrite a newer record.

This is a correctness gap, not application policy. The persistent counter
cannot complete its version-conflict case until persistence has an atomic
conditional write contract.

### 2. Scheduler has no durable occurrence identity

CRON state and runtime reconciliation work after restore. However, the runtime
reuses static Signal data and generates a fresh Signal ID for each dispatch.
There is no stable identity for one logical time occurrence across a crash,
retry, or redelivery.

The application can deduplicate an occurrence ID when it receives one. It
cannot create the correct ID after the Scheduler has already lost the delivery
boundary.

### 3. Scheduler has no durable delivery acknowledgement

The runtime casts a due Signal and does not record dispatch intent or
acknowledgement. A crash near dispatch can lose an occurrence or create a new
unrelated delivery after restore. Durable scheduling needs an explicit
at-least-once rule and a missed-window policy.

### 4. Keyed one-shot replacement needs a custom Plugin

Burst Buncher needs one replaceable inactivity timer. The existing Scheduler
can create a delayed Signal, but it cannot replace or cancel one keyed delayed
timer. The example therefore defines a Timer Plugin, Replace and Cancel
Directives, and a runtime process.

The Plugin boundary is correct because a timer is a real OTP capability. The
missing part is a small built-in keyed timer operation, not a more general
Plugin abstraction.

### 5. Duplicate success still creates a commit

Persistent Counter and Durable Schedule return the same Agent state for a
duplicate stable ID. The Server treats this as a successful commit and advances
the commit revision. The Server and persistence documentation now state this
rule. Persistent Counter loads the stored record after the identical-state
commit, before hibernation, and then restores it again. Both retain revision 2.
Invalid input changes neither state nor stored revision. This resolves the
contract gap in [issue #15](https://github.com/mikehostetler/jido_v3/issues/15).
An Action can return `{:error, reason}` when duplicate rejection must prevent
a commit. The stale-writer test was skipped during this burn-in. The later
[persistence fix](persistence-write-results.md) adds compare-and-swap writes
and enables that test.

### 6. Runtime time needs a test seam

Scheduler validation and CRON activation use the real timezone database and
wall clock. The tests avoid waiting by using a far-future CRON expression and
manually applying identified occurrences. A clock boundary would make due,
missed, and repeated occurrence tests fully controlled.

## What Jido should not own

- Batch item identity or maximum batch size
- Duplicate command ledger retention policy
- ReAct prompt design or tool selection policy
- ReAct maximum step count
- Business meaning of a schedule occurrence
- Application response to missed schedule windows

Jido should own serialized Turns, runtime capability lifecycle, durable write
authority, and a clear scheduled-delivery contract.

## Group D result

| Example | Result | Main contract tested |
| --- | --- | --- |
| Human Approval Gate | passed | Plain pending work resumes through a later Signal; no suspended Flow contract is needed |
| Causal Audit Tree | doesn't work yet | Manual proof data passes; automatic runtime and child lifecycle capture are missing |

The approval example keeps policy in application state and uses an idempotent
tool key. The causal audit example defines explicit proof and analysis data.
It does not change core Jido or claim that event order proves causation.
