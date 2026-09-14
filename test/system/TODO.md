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

## Last verified status (2026-09-14, seed 0 unless noted)

| Command | Result |
| --- | --- |
| `mix quality` | 1,106 core tests pass; format, compile, Credo, and Dialyzer pass |
| `mix test.authoring` | 523/523 pass |
| `mix test.bench` | 7/7 pass; these are benchmark contract tests, not a load run |
| `mix test.system` | 112/113 pass; only `SYSTEM-CLUSTER-01` fails |
| `mix test.all --cover` | 2,015/2,016 pass; only `SYSTEM-CLUSTER-01` fails; 93.5% coverage, 1 skipped and 115 excluded |
| `mix test.services` | 84/86 pass; `SYSTEM-BEDROCK-01` and `SYSTEM-BEDROCK-04` fail |
| `mix test.services.minio` via owned local MinIO | 28/29 pass; `SYSTEM-BEDROCK-05` fails and native upload reports two `Jason.EncodeError` results (`SYSTEM-BEDROCK-03`) |
| Direct S3/MinIO pressure repeats (2026-09-14) | Four fresh 2/2 runs pass |
| Two burn-in runs, 20 rounds each (2026-09-13) | 8 selected tests pass; 1,086 model commands and 6 BEAM crashes |

These runs used the Jido changes now committed locally on `v3-spike`. The
Topology target and owned-Agent probes
`SYSTEM-TOPOLOGY-01/02/03` now pass. Bedrock replacement
`SYSTEM-BEDROCK-02` passes with Bedrock 0.7.2.
The supervisor and Bus probes also passed, but their changes still need review
and repeated runs before the earlier timing failures can be closed.
`SYSTEM-CLUSTER-01` is tagged `:flaky` for tracking, but its current failure is
repeatable: it tests a cluster-wide owner guarantee that Jido core does not
provide. It remains enabled in `mix test.all`. The approved `DIST-03` core skip
is unchanged. Strict Bedrock
startup and MinIO snapshot recovery still block their later assertions. No
failed probe was skipped or replaced with an in-memory adapter.

## Topology target durability — verified paths and open edges

The accepted target now has a versioned record. The Controller saves it before
it acknowledges an update, and it restores membership after Runtime and
whole-Jido replacement. Owned added Agents are stopped during cleanup.
`SYSTEM-TOPOLOGY-01/02/03` pass on the local and service adapters selected
above. These results do not prove every target lifecycle rule.

- [x] Save a stable, versioned target before acknowledging its update. Use CAS
      for a durable adapter and stop the update after an unknown write result.
- [x] Restore accepted membership after Runtime and whole-Jido replacement;
      retain existing Agent checkpoint identities.
- [x] Stop owned added Agents during Controller shutdown and partial cleanup.
- [ ] Define and test explicit replacement, deletion, tombstones, incompatible
      definitions, and required/optional restore.
- [ ] Reconstruct an accepted target in a fresh BEAM, not only a restarted Jido
      tree, and check the saved revision and ownership.
- [ ] Check stale revisions, malformed target records, and unknown CAS outcomes
      against the saved target. Readiness must not hide an older revision.

Do not infer cluster-wide ownership from a durable target record.

## Immediate supervisor replacement — under verification

An ungated `Process.exit(jido_supervisor, :kill)` can let its parent start a new
Jido tree while old children still hold registered names. The default parent
restart budget can be exhausted before those children exit. This was observed
while developing the full-Jido probe. Its parent barrier now separates that
failure from lost durable targets.

- [x] Add a dedicated enabled reproduction with an explicitly held old child
      shutdown, so the name-release race is deterministic.
- [x] Capture the old child's shutdown with monitors and verify the replacement
      Jido tree and saved checkpoint after the child releases its name.
- [x] Wait for old named Jido children to stop before a replacement claims
      those names. The held-child probe now passes without a sleep or a raised
      restart budget.
- [ ] Review and repeat the replacement probe on the committed code. Check a
      held child that does not stop before the bounded wait.

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
      target recovery probes. The enabled probe checks owned-member cleanup
      and `SYSTEM-TOPOLOGY-03` now passes.
- [x] Repair partial-update cleanup and durable target recovery so shutdown
      removes owned resources and readiness reports the accepted target.
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
      and controller failure during an accepted update. The three named
      `SYSTEM-TOPOLOGY` probes now pass on the selected adapters.
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

## Bus replay and replacement readiness — under verification

Earlier runs timed out during durable Bus replay or after a Runtime/Bus
replacement on Redis and ETS. The latest full local and service runs pass with
the nonblocking Client delivery change. One passing run does not prove
that these timing failures are gone.

- [ ] Run repeated fresh-BEAM seeds for durable input replay, included-team
      replacement, and shared-Bus replacement on the committed Client change.
      Keep the same readiness call and timeout.
- [ ] If a timeout returns, capture Controller status and component errors.
      Check that each durable record has one completed or pending delivery and
      that no delivery worker remains after Client shutdown.

## Authoring follow-ups

The 26 saved Agent and Topology cases use six forms and all 523 current tests
pass. Add cases for a named contract, not to reach a fixture count.

- [ ] Compile and extract definitions in one fresh BEAM, transfer saved JSON
      and Registry references to a second fresh BEAM, and verify construction
      and stable results there.
- [ ] Run bounded recompilation loops with isolated module names and check
      diagnostics, module reuse, and later valid compilation after failure.
- [ ] Generate bounded invalid Agent inputs and nested Topology inputs from
      small independent models. Keep failing seeds and reduce them to a saved
      regression case.
- [ ] Decide whether explicit nil in Agent state defaults means missing or a
      supplied value. The current focused test records the existing behavior.

## Load follow-ups

The seven benchmark tests check the measurement tools. The system burn-in
selects eight model/peer tests; it is not a sustained mixed runtime workload.

- [ ] Add one opt-in, seeded run with concurrent Agent calls, Bus replacement,
      Topology updates, and supervised restarts. Account for every accepted
      request and check saved revisions and effect IDs.
- [ ] Sample process, mailbox, memory, and stored-record growth through the
      run and after cleanup. Keep timing measurements separate from correctness
      assertions; do not set a hard latency gate from one host.
- [ ] Repeat the workload against a real shared store in the opt-in service
      profile after the local run is stable. Keep external services out of
      `mix test.all`.

## Adapter and observability expansion

- [x] Run Ecto with PostgreSQL as well as the current real SQLite fixture.
- [x] Exercise Redis server restart from AOF and lost socket replies during
      Lua execution; exercise File temporary-write and rename failure.
- [x] Exercise real Bedrock log/coordinator replacement, transaction aborts,
      lost commit replies, and repeated startup with one cluster identity. Keep
      the local relaxed profile's limits explicit. `SYSTEM-BEDROCK-02` passes
      with Bedrock 0.7.2.
- [ ] Complete strict multi-node Bedrock durability checks. The probe is
      implemented but `SYSTEM-BEDROCK-04` blocks it at startup. Track the
      upstream defect in [Bedrock #319](https://github.com/bedrock-kv/bedrock/issues/319)
      and Jido verification in [Jido #370](https://github.com/agentjido/jido/issues/370).
- [x] Check Bedrock's own shutdown contract for the placeholder outside its
      cluster supervisor. It survived cluster shutdown in this fixture. Current
      cleanup explicitly stops that owned process before reusing the identity;
      the enabled probe exposes `SYSTEM-BEDROCK-01`.
- [ ] Fix Bedrock's placeholder lifetime and verify unassisted cluster
      shutdown. Keep fixture cleanup as a control, not proof of the contract.
- [x] Add a separate opt-in Bedrock/MinIO profile for snapshot upload and
      recovery after cluster rebuild. Require an explicit test endpoint and
      credentials, isolate each run's bucket or prefix, and check owned-object
      cleanup. Keep it out of `mix test.all`.
- [ ] Prove native Bedrock snapshot upload and cold rebuild recovery. The
      profile exposes `SYSTEM-BEDROCK-03` and `SYSTEM-BEDROCK-05`; the binary
      upload control is not a production fix. Separate the upload encoding
      error from the later rebuilt-cluster readiness failure.
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
