# Runtime system test work

Keep each new scenario tied to an explicit state, effect, resource, and
observability invariant. Preserve failures until the owning contract is fixed.
Local scenarios run with `mix test.system` and `mix test.all`. Redis and real
Bedrock scenarios run only when selected with `mix test.services` or an explicit
service file/filter. MinIO has a separate opt-in profile and is not required.
See [SCENARIOS.md](SCENARIOS.md) for implementation and run evidence. A checked
item means that the probe was implemented and run; it does not mean that the
contract passed or that a core defect was fixed. Open items include blocked
assertions and core work.

## Last verified status (seed 0 unless noted)

| Command | Result |
| --- | --- |
| `mix quality` (2026-09-14) | 1,104 core tests pass; format, compile, Credo, and Dialyzer pass |
| `mix test.system` (2026-09-14) | 101/113 pass; 12 enabled failures, including one shared-Bus replacement readiness timeout |
| `mix test.all --cover` (2026-09-13, before S3 commit) | 1,991/2,003 pass; 12 enabled failures; 94.1% coverage; 1 skipped and 87 service tests excluded; not rerun after S3 commit |
| `mix test.services` (2026-09-14, explicit Redis binary) | 76/86 pass; 10 enabled failures |
| `mix test.services.minio` via owned local MinIO (2026-09-14) | 26/29 pass; two Topology target failures and one Bedrock rebuild-readiness failure; native upload also reports two encoding errors |
| Direct S3/MinIO pressure repeats (2026-09-14) | Four fresh 2/2 runs pass |
| Two burn-in runs, 20 rounds each (2026-09-13) | 8 selected tests pass; 1,086 model commands and 6 BEAM crashes |

The local failures are `SYSTEM-TOPOLOGY-01/02` on ETS, File, and SQLite,
`SYSTEM-TOPOLOGY-03`, `SYSTEM-SUPERVISION-01`, and `SYSTEM-CLUSTER-01`.
In the latest local run, `SYSTEM-BUS-01` timed out on File and SQLite, and an
included-team Bus replacement timed out on ETS. Earlier runs saw replay
timeouts on other adapters. Both readiness failures depend on run timing. The
base service failures are `SYSTEM-TOPOLOGY-01/02` on Redis, PostgreSQL, and
Bedrock, plus `SYSTEM-BEDROCK-01/02/04`. The MinIO profile also has two S3
Topology target failures. Its snapshot test observed `SYSTEM-BEDROCK-03` twice,
then failed at `SYSTEM-BEDROCK-05`; it did not reach the downstream Agent
restore assertions. None of these failures was skipped or fixed by this
test-status update.

## Topology target durability — open

The enabled `SYSTEM-TOPOLOGY-01` and `SYSTEM-TOPOLOGY-02` tests reproduce lost
accepted targets. `Controller.Runtime` stores the accepted update only in its
own state. Its supervisor restarts it with the original child arguments.
`Jido.RuntimeStore` retains placement hints within one Jido activation, not a
durable desired Topology. Persistence adapters store Agent records, not targets.

- [ ] Define a versioned Topology target record, stable identity, and revision.
- [ ] Define when an update is accepted: persist the target before acknowledging
      it, then reconcile resources and members from that accepted revision.
- [ ] Use CAS and stop or reject work after an indeterminate target write.
- [ ] Define required/optional restore, incompatible definitions, explicit
      replacement, deletion, and tombstone behavior.
- [ ] Recover membership and ownership after Runtime, Controller, whole-Jido,
      and BEAM failure; retain the existing Agent checkpoint identities.
- [ ] Make shutdown account for every owned Agent, including added members.
- [ ] Emit the accepted and restored target revision so readiness cannot conceal
      a fallback to an older desired state.

A local cache alone would not repair the durable contract. Do not report this
work as solved by retaining a target only while a Jido supervisor remains alive.

## Immediate supervisor replacement — open

An ungated `Process.exit(jido_supervisor, :kill)` can let its parent start a new
Jido tree while old children still hold registered names. The default parent
restart budget can be exhausted before those children exit. This was observed
while developing the full-Jido probe. Its parent barrier now separates that
failure from lost durable targets.

- [x] Add a dedicated enabled reproduction with an explicitly held old child
      shutdown, so the name-release race is deterministic.
- [x] Capture the parent shutdown reason and failed child starts with monitors
      and scoped logs. Verify the final supervision state separately.
- [ ] Decide which application supervision contract owns safe replacement;
      do not hide this by raising restart intensity or inserting a sleep.

## Runtime stress and chaos tests

Test combined runtime failures, especially failures during recovery. Start with
repeated recovery and late work from an old activation before adding more
adapters or longer runs. A checked probe can still expose an open core defect.

- [x] Fail recovery twice. Complete an external effect, lose its reply, restart,
      reject the effect confirmation write, then restart again. Check that
      pending work survives, effect IDs remain stable, and replay follows the
      stated deduplication contract. Check each saved revision.
- [x] Release an old storage request after replacement or deletion. Check that
      it cannot overwrite a newer revision or revive deleted work.
- [ ] Hold and release an old result or acknowledgement after replacement.
      Check saved revisions and effects as well as live Agent state.
- [x] Check cancellation and Turn timeout before commit, and queued cancellation
      or caller timeout while a checkpoint write is held. Release the write,
      restart, and compare responses, saved state, effects, and recovery.
- [ ] Race a Turn deadline with the held checkpoint commit itself. Define the
      outcome on each side of that commit boundary.
- [x] Crash during a partial Topology update. Start some new members, fail one
      resource, then kill the Controller during cleanup. Extend the existing
      target recovery probes. The enabled probe records surviving owned members
      and `SYSTEM-TOPOLOGY-03` after control-tree failure.
- [ ] Repair partial-update cleanup and durable target recovery so shutdown
      removes owned resources and readiness cannot hide missing resources or
      an older accepted target.
- [x] Fail actual storage during recovery. Fail a File rename, corrupt a saved
      record, or lose a reply after the storage server accepts a write. Inject
      these faults below the adapter wrapper. Check for explicit restore errors
      instead of a silent reset to initial state. An uncertain write must
      prevent unsafe continuation. Apply each adapter's stated durability
      limits; keep service-backed cases in the opt-in service suite.
- [x] Combine overload and replacement. Fill request queues, cancel callers,
      replace the Bus, and crash an active worker. Account for every admitted
      request with a reply, rejection, cancellation, or explicit process-failure
      outcome. Check for unresolved callers, abandoned tasks, and mailbox
      growth after recovery and cleanup.

Use these checks and controls for every runtime stress and chaos scenario:

- [x] Support ordered fault sequences across restarts. The current wrapper
      consumes one matching fault, then returns to normal operation. Keep that
      simple mode and add controlled failures during recovery.
- [x] Use explicit barriers, acknowledgements, and process monitors to control
      fault boundaries. Scoped logs can identify service readiness; follow
      them with a protocol or state check. Do not use sleep timers or polling.
      Record seeds for varied sequences and reduce failures to a short replay.
- [x] Check effect attempt history as well as final sink records. A sink that
      removes duplicates does not prove that an effect was attempted once.
      Do not infer exactly-once execution for arbitrary external effects.
- [x] Check observability in each scenario. Reported revisions, outcomes, and
      effect IDs must agree with saved state and observed effects. Distinguish
      an interrupted operation from successful completion. Capture logs when
      testing log or redaction behavior; keep state and effect checks separate.
- [x] State the contract under test and the expected failure evidence. Separate
      regressions from unsupported guarantees, including exclusive cluster
      ownership. A deliberately killed process is not itself a core defect.

## Broader scenarios

- [ ] Complete the crash-boundary matrix around Turn commit, checkpoint
      replacement, external effect, acknowledgement, and response delivery.
      The suite covers selected pre/post-commit faults, effect reply loss, Bus
      acknowledgement failure, storage server loss, disk errors, and corruption;
      it does not cover every before/during/after combination.
- [x] Add model-based Turn sequences with a small independent state oracle.
      Mix success, rejection, cancellation, deadlines, conflict, deletion,
      restart, and replay. Record the seed and shrink failing sequences.
- [x] Extend live Topology lifecycle tests to component includes, logical
      ownership, partial startup, exact local placement, shared Bus replacement,
      and controller failure during an accepted update. Open failures are
      recorded as `SYSTEM-TOPOLOGY-01` through `SYSTEM-TOPOLOGY-03`.
- [ ] Add explicit resource replacement and other ownership policies beyond
      the tested logical ownership case.
- [x] Extend the Signal journey through validation, serialization, Router,
      normal and durable Bus input, Action/Flow, commit, Directive dispatch,
      acknowledgement failure, replay, and trace propagation.
- [x] Add long seeded burn-in with bounded failure artifacts, process and
      memory counts, mailbox growth, storage growth, and repeated full BEAM
      reconstruction. Reuse the deterministic scenarios before adding a new
      test framework.

## Multi-node runtime stress and network partitions

Core owns safe execution on an explicitly selected remote node, accurate
operation outcomes, stale-write rejection, and the declared parent/child
lifecycle. Extend the existing peer tests; do not duplicate their basic remote
placement and disconnect checks.

- [x] Hold remote child startup behind its target supervisor until the parent
      request times out. Start the child, disconnect before the parent handles
      its late startup notification, then reconnect and retry. Check child
      identity, ownership, late notifications, and cleanup. The uncertain
      outcome causes no local fallback or untracked duplicate.
- [x] Disconnect during remote work held before commit. Check the caller
      outcome, remote child and execution-task cleanup, saved revision, and
      interrupted Turn events under the declared lifecycle policy.
- [ ] Disconnect after a remote commit may have occurred but before its reply
      arrives. Check saved state and external effects; do not treat a lost
      connection as proof that the remote work never committed.
- [x] Partition two peers that can both reach the same real Redis store while
      the old Agent holds work before commit. Explicitly start a replacement on
      the other peer, commit revision two, reconnect, and release the old write.
      The old call returns a persistence conflict and cannot overwrite the new
      checkpoint. This does not prove exclusive ownership or automatic failover.
- [ ] Combine that shared-store stale-write case with an owned remote child's
      held lifecycle messages and an effectful Turn. The local partition probe
      already rejects a late child-start message after replacement, but it does
      not combine that message with the shared-Redis checkpoint race.
- [x] Keep test control separate from the connection under test. Reuse the
      independent peer control channel, hold the data connection unavailable
      through each fault boundary, and verify that it does not reconnect early.
      One `Node.disconnect/1` call alone does not prove a sustained partition.
      Use barriers and node/process monitors, not sleep timers or polling.
- [x] Record per-node state, saved revisions, lifecycle events, and cleanup
      evidence for the implemented partition cases. Keep observation available
      during the split and distinguish interrupted work from completed work.
- [ ] Add effect IDs and per-node effect evidence to an effectful stale-activation
      case. The shared-Redis case records the held Signal ID, call outcome,
      revisions, Turn events, and empty effect sink, but has no external effect.

Keep membership discovery, node selection, automatic failover, rebalance, and
partition/rejoin policy in the proposed `jido_cluster` package. That package
must test coordination through Jido's public APIs. Leases and durable write
authority require storage or an explicit authority service; a location registry
or checkpoint alone does not provide them. Preserve the approved DIST-03 skip
for exclusive cluster ownership. These core scenarios must not introduce that
guarantee or new cluster policy.

## Intermittent Bus replacement readiness — open

One system run reached the default 60-second Controller readiness timeout after
a Runtime/Bus replacement on the Redis fixture. The Redis process cleanup check
passed. Ten focused fresh-BEAM runs with seeds 1 through 10 then passed with the
same readiness call and timeout; later runs with seeds 0, 7, and 19 also passed.
The 2026-09-14 local run reached the same timeout for an included-team Bus
replacement on ETS. This is not evidence of a repair or of an adapter defect.
The failed component was not captured in either timed-out run.

- [ ] Reproduce it with `mix test test/system/services/redis_test.exs --only
      scenario:bus_recovery --seed 0`. Failure includes Controller status and
      component errors. Supply the Redis executable as needed.
- [ ] Establish the failed activation boundary before changing core behavior.
      Capture Controller status and component errors for both the included-team
      and shared-Bus replacement paths.
      Keep manual repair mode, the readiness call, and timeout unchanged while
      isolating the cause; do not hide it with retries or a skip.

## Adapter and observability expansion

- [x] Run Ecto with PostgreSQL as well as the current real SQLite fixture.
- [x] Exercise Redis server restart from AOF and lost socket replies during
      Lua execution; exercise File temporary-write and rename failure.
- [x] Exercise real Bedrock log/coordinator replacement, transaction aborts,
      lost commit replies, and repeated startup with one cluster identity. Keep
      the local relaxed profile's limits explicit. Replacement exposes
      `SYSTEM-BEDROCK-02`.
- [ ] Complete strict multi-node Bedrock durability checks. The probe is
      implemented but `SYSTEM-BEDROCK-04` blocks it at startup.
- [x] Check Bedrock's own shutdown contract for the placeholder outside its
      cluster supervisor. It survived cluster shutdown in this fixture. Current
      cleanup explicitly stops that owned process before reusing the identity;
      the enabled probe exposes `SYSTEM-BEDROCK-01`.
- [x] Add a separate opt-in Bedrock/MinIO profile for snapshot upload and
      recovery after cluster rebuild. Require an explicit test endpoint and
      credentials, isolate each run's bucket or prefix, and check owned-object
      cleanup. Keep it out of `mix test.all`.
- [ ] Prove native Bedrock snapshot upload and cold rebuild recovery. The
      profile exposes `SYSTEM-BEDROCK-03` and `SYSTEM-BEDROCK-05`; the binary
      upload control is not a production fix.
- [x] Add physical-delete failures, tombstone races during restoration,
      persistence Plugin migration failure, and stale checkpoint replacement.
- [x] Check semantic event completeness during cancellation and overload, and
      across node loss. Distinguish an interrupted span from a completed one.
- [x] Check exported OpenTelemetry parentage, metric counters and gauges,
      redacted structured logs, handler/exporter failure, and observer overhead.
- [x] Save a compact per-run result with adapter, seed, fault boundary, state
      revision, effect IDs, resource counts, and interrupted operation IDs.

No service failure may become an automatic skip or an in-memory substitute.
Record its exact prerequisite, failing operation, and observed error.
