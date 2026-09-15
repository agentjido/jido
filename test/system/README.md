# System verification

This suite checks runtime invariants across real components. It is separate
from pure authoring checks and focused core regressions.

The commit projection scenario checks the optional Plugin `after_commit/3`
hook with ETS, File, and SQLite/Ecto. It compares live owned state, saved
revisions, restore, hook settlement events, scoped semantic logs, and cleanup.

```sh
mix test.system    # Local ETS, File, and SQLite/Ecto scenarios
mix test.all       # All normal suites, including local system scenarios
mix test.services  # Opt-in Redis, PostgreSQL, and real Bedrock scenarios
mix test.services.minio # Separate opt-in direct S3 and Bedrock snapshot profile
```

`mix test.all` does not start Redis, PostgreSQL, MinIO, or a real Bedrock cluster. Service tests
have only the `:service` tag; local system tests have only `:system`.
Plain `mix test` and `mix quality` exclude both tags. There is no new CI job.
The local cluster-authority probe is skipped by user direction. The base
service profile passes with all 33 real Bedrock tests skipped. The MinIO profile
passes on repeat with its Bedrock snapshot test skipped. The known placeholder,
strict-startup, upload, and cold-rebuild gaps remain. See
[the implementation record](SCENARIOS.md) for current evidence.

## Layout

```text
system/
  runtime/                  # :system; included in mix test.all
    agents_test.exs
    commit_projection_test.exs
    topology_test.exs
    observability_test.exs
    file_storage_test.exs
    turn_model_test.exs
    supervision_test.exs
    open_telemetry_test.exs
    signal_journey_test.exs
    topology_cleanup_test.exs
    peers_test.exs
  services/                 # :service; explicit opt-in only
    redis_test.exs
    redis_faults_test.exs
    redis_partition_test.exs
    postgres_test.exs
    bedrock_test.exs
    bedrock_restart_test.exs
    bedrock_faults_test.exs
    bedrock_transactions_test.exs
    bedrock_strict_test.exs
    minio/                  # Only test.services.minio selects this directory
      snapshots_test.exs
      s3_test.exs
      s3_pressure_test.exs
  support/
    adapters.exs            # Real storage setup
    redis.exs               # Owned Redis process and RESP client
    case.exs                # Isolated runtime and fault controls
    fault_adapter.exs       # Controlled checkpoint boundary
    observability.exs       # Scoped telemetry and log recorder
    report.exs              # Compact per-run JSON evidence
    turn_model.exs          # Independent state oracle and failure reduction
    scenarios/              # Shared assertions, used by both profiles
      checkpoints.exs
      effects.exs
      fencing.exs
      recovery.exs
      execution.exs
      restoration.exs
      overload.exs
      topology.exs
  README.md
  TODO.md
  SCENARIOS.md              # Implementation status and verification evidence
  burn_in.exs               # Optional fresh-BEAM seeded repetition
  run_s3_minio_local.py     # Start and stop an owned local MinIO test server
```

Shared Ecto, Bedrock, and recoverable-delivery fixtures live in `test/support/`.
Scenario modules define tests through `use`; each entry module selects its
adapter and profile. Add common faults to the scenario modules, not separate
copies for each service. Focused core regressions stay in `test/jido/`.
Core Bedrock adapter tests use deterministic transaction fixtures. The actual
cluster conformance and restart test belongs to the opt-in service profile.

## Storage profiles and prerequisites

All seven adapters run the same 21 Agent scenarios and four Topology
scenarios. No adapter is replaced by an in-memory simulation.

| Adapter | Profile | Fixture and boundary |
| --- | --- | --- |
| ETS | Local | A supervised table owner outside the Jido tree. Jido restart is covered; BEAM or table-owner loss is not durable. |
| File | Local | A private per-test directory, with one BEAM writer as required by the adapter. |
| Ecto | Local | Real SQLite repo, WAL mode, four connections, and migrations. |
| PostgreSQL/Ecto | Opt-in service | Owned Docker container, loopback-only ephemeral port, empty database, four connections, real migrations. |
| Redis | Opt-in service | A private `redis-server` process, Unix socket, AOF, and `appendfsync always`. The adapter sends its real Lua CAS script. |
| Bedrock | Opt-in service | A real local cluster, coordinator, log, materializer, and transaction repo. The relaxed single-node profile does not prove strict multi-node or power-loss durability. |
| S3 | Opt-in MinIO service | An isolated bucket and prefix on an explicit S3-compatible endpoint. Single-object GET and conditional PUT use a signed client with one attempt. The adapter limits objects to 5,000,000 bytes. |

Run `mix deps.get` first. Test dependencies must compile even when service tests
are excluded; exclusion prevents service startup, not dependency compilation.
Local scenarios need no external storage server.
Bedrock needs `epmd` and local Erlang distribution. Redis needs a working
`redis-server` on `PATH`, or an explicit executable:

```sh
JIDO_SYSTEM_REDIS_SERVER=/absolute/path/to/redis-server mix test.services
```

The Redis client in this suite implements only the RESP replies used by the
adapter. Each command opens its own socket, so concurrent CAS tests exercise
the Redis server, not a test-side lock. The helper never connects to an existing
Redis service. It owns and stops its child process and removes its socket.
Cleanup also checks that the owned Redis OS process has exited.
Redis fault tests kill the server and restore from AOF. A one-command TCP proxy
also drops an accepted Lua write's reply by closing the downstream socket.
No global tool-version setting is changed. Once a service profile is selected,
a missing prerequisite fails setup; it is never skipped or replaced by a fake.

PostgreSQL requires a running Docker daemon and the local `postgres:17-alpine`
image. Select another compatible local image with `JIDO_SYSTEM_POSTGRES_IMAGE`.
The fixture uses `--pull=never`; it does not install or pull an image. It creates
and removes only its own randomly named container. Startup waits for the final
PostgreSQL readiness log, then checks `SELECT 1` before running migrations.

Bedrock uses distinct service identities for distinct empty test clusters.
The cluster restart fixture retains one identity and its data directory.
Application-level object storage is also isolated and restored during cleanup.
The fixture explicitly stops Bedrock's placeholder after the cluster supervisor
stops, because it can survive the Distributor's normal exit. Cluster restart
checks storage recovery after fixture cleanup, not unassisted Bedrock shutdown.

### Strict Bedrock and MinIO profiles

The base service command contains a strict Bedrock probe on three isolated
BEAM nodes. Each has a persistent coordinator and worker directory. A shared
test bootstrap requests three logs and three replicas. It checks actual log
placement before node loss and required Agent restoration. Startup currently
failed in Bedrock before those durability checks could run (`SYSTEM-BEDROCK-04`).
It is skipped with the full real Bedrock service suite pending upstream fixes.
This is not evidence of
strict durability. All peers run on one host; this test
does not simulate independent disks, physical power loss, or network partition.

MinIO is a separate profile. Start a dedicated test service, then provide its
endpoint and credentials explicitly. The fixture does not start MinIO or use
ambient AWS credentials:

```sh
JIDO_SYSTEM_MINIO_URL=http://127.0.0.1:9000 \
JIDO_SYSTEM_MINIO_ACCESS_KEY=your-test-access-key \
JIDO_SYSTEM_MINIO_SECRET_KEY=your-test-secret-key \
mix test.services.minio
```

Use test-only credentials with bucket create, list, get, put and delete rights.
The fixture creates one randomly named bucket, checks real S3 requests, and
removes only that bucket and its objects. Missing configuration fails setup.
The base `mix test.services` command selects only top-level service files, so
it does not require MinIO. Both service commands remain outside `mix test.all`.

The MinIO snapshot probe uses real materializer data and compacted snapshot files. It
advances the real durable window with zero test lag instead of waiting for a
timer. Native upload currently fails (`SYSTEM-BEDROCK-03`). An explicit control
uploads the same files as binary, then rebuilds the cluster with cold
materializers. Coordinator metadata and log WAL are retained. The rebuild also
fails to reach readiness (`SYSTEM-BEDROCK-05`), so snapshot recovery is not yet
proved. The snapshot test is skipped pending upstream fixes;
neither control is a production fix or an in-memory substitute.

The direct S3 profile uses the same 21 Agent and four Topology scenarios as
the other adapters, plus a physical-deletion probe. It checks conditional
writes, saved revisions, pending effects, restoration, resources, and
semantic telemetry against real object storage. The fixture passes a
single-attempt signed request function to
`Jido.Persistence.S3`. A lost write reply remains indeterminate. The client
must return SHA-256 checksums on GET and support `If-Match` and
`If-None-Match` on PUT. Run only this profile with:

```sh
mix test test/system/services/minio/s3_test.exs --only service --seed 0
```

The run report records GET, PUT, and DELETE request counts per scenario. A
create uses one PUT. A validated read followed by a token write uses one GET
and one PUT, plus any reads for identity selection. Direct byte CAS uses its
own GET before the conditional PUT.

Run the separate local pressure test after the shared S3 scenarios:

```sh
python3 test/system/run_s3_minio_local.py
```

It races 48 object creates, then 24 token writers at each of eight object
updates and 24 checkpoint writers at each of eight Agent revisions. Each
round must have one winner. It also lets MinIO accept a write, drops the
reply, and checks that Jido does not retry it. The tests check the stored
Agent, restoration, one effect attempt, resources, and semantic telemetry.
The runner requires a local `minio` binary. It creates a temporary service
and test credentials, then stops that service and removes its data. Pass an
explicit test path to run another MinIO file.

On 2026-09-14, four fresh local MinIO runs passed both pressure tests. The
first run made 690 GET, 382 PUT, and one DELETE request. Request counts can
change with the order of concurrent work.

An earlier local MinIO `RELEASE.2025-10-15T17-29-55Z` run used one
loopback HTTP endpoint, one owned bucket per test, explicit test credentials,
single-attempt ExAws `2.7.0` requests, and the default object-size limit. It
passed 24 of 26 direct S3 scenarios before the Topology target fix. It made
628 GET, 139 PUT, and two DELETE requests. These historical counts include
identity reads and can change with runtime ordering.

The latest full local MinIO profile on 2026-09-14 passed 28 tests and skipped
the Bedrock snapshot test on repeat. The first run had one direct S3 Topology
readiness timeout, which did not repeat. An earlier Bedrock snapshot run failed
cold rebuild and recorded two native-upload encoding errors. The runner
removed its owned test service and data after each run.

Record the MinIO release and endpoint settings used for each later conformance run.
A MinIO result does not prove AWS S3 conformance. The profile does not test
multipart upload, listing for recovery, bucket versioning, object expiry, or
cross-region replication. Do not expire active records or tombstones in the
persistence prefix.

## Invariants

- A crash before checkpoint storage retains revision zero and emits no effect.
- A crash after storage but before its reply retains revision one and pending
  intent. Restore completes that intent and advances to revision two.
- An indeterminate write stops the old activation. It cannot execute another
  Turn on stale state or dispatch an unconfirmed Directive.
- Effect attempts can repeat. The example Plugin keeps durable intent, and
  its sink deduplicates a stable effect ID. One sink record is the invariant;
  this is not a claim that arbitrary external effects execute exactly once.
- Rejected completion storage leaves intent available for recovery.
- Eight competing writers have exactly one CAS winner. A stale live Agent is
  fenced before it emits an effect. A tombstone also fences delayed writes.
- A replaced Bus is subscribed before Topology reports ready. A traced Signal
  reaches every member, commits one Turn per member, and retains trace identity.
- Killed Agent tasks, Plugin workers, and runtime-pool wrappers terminate.
  Intentional Controller shutdown must remove all of its owned members.

Ordering comes from replies, monitored exits, checkpoint/effect barriers,
semantic events, and scoped service logs. There are no sleep timers or repeated
polling in the system scenarios. Timeouts are failure deadlines, not evidence
of completion. After an event, check the actual state or protocol once.
Redis waits for its startup log, then checks `PING`. Bedrock waits for layout
publication and startup message barriers, then checks a real transaction.

## Observability on every scenario

A per-test recorder watches Turn, Agent lifecycle, commit, Plugin commit
notification, Directive, persistence, and Topology semantic events. It checks bounded metadata, integer measurements,
non-negative duration, outcome status, balanced spans, and no duplicate terminal
events. Selected Turns must start at evaluation and have one commit span. Successful
and failed writes must have the expected persistence classification.
Every scenario must emit Turn, lifecycle, commit, and persistence events. A
detached recorder fails cleanup; partial observation cannot count as a pass.

The recorder stays active through supervised cleanup. A missing terminal event
is accepted only for the exact deliberately killed process, after its death is
confirmed. Such an interrupted operation is not represented as a completed one.
The Bus scenario also checks Signal/Turn identity and trace continuity after
the members stop, so late duplicate Turns cannot escape the count assertion.
The same observer records Logger events from each test's isolated process
group, plus output from its owned Redis process. Use `await_log/3` for a known
log event and `logs/1` for evidence. Event waits first search recorded history,
then receive new events under one deadline. Timeouts include recent logs.
Logs can establish service readiness but do not replace state, effect, or
telemetry assertions. The SDK tests use a real simple span processor and PID
exporter. They check exported parentage and failure isolation without contacting
an external collector. The SDK dependency is test-only and does not start by
default. Metric tests check public counters and a host-defined revision gauge;
log tests check identity and payload redaction. The SDK overhead test records
paired timings without asserting a noisy timing ratio.

Peer tests collect semantic events over an independent standard-IO control
channel. Before SIGKILL they record the held Turn's start; a surviving peer
then confirms node loss. Those interrupted Turns are reported separately, not
as completed local spans. The File reconstruction case never has simultaneous
writers to the same directory. The ownership probe deliberately uses separate
stores; it does not claim File supplies distributed fencing.
Partition tests block each peer's cookie for the other node, disconnect the
data link, and check both node lists at the fault boundary. Their standard-IO
control links remain available. One test holds a remote Turn and checks its
cancelled outcome, unchanged checkpoint, child/task cleanup, closed spawn
request, explicit replacement, and rejection of a late child-start message.
A second test holds a remote spawn while the target supervisor is suspended,
lets the child start after the reply deadline, then partitions the nodes and
checks cleanup and explicit replacement. The Redis service test uses one real
shared store: a replacement commits a newer revision during the split, and
the old Agent's held write fails after rejoin. These tests do not elect an
owner or choose a replacement automatically.

Each run writes a compact JSON report to ignored `tmp/system-runs/`. It includes
adapter, seed, fault boundary, revisions, effect attempts/IDs, event counts,
resource counts, and interrupted operation IDs. Lists are bounded. Raw Agent
state, Signal data, credentials, and logs are not copied into the report.
Helper-only and excluded tests have `observed: false`; that is not a claim of
complete observation. A missing reporter fails observed-scenario cleanup.

## Findings and open contracts

The suite found a core readiness defect: a retained Agent could remain
disconnected from a replaced Bus after the Controller reported ready. The fix
checks its Bus input Plugin and reconnects the Client before readiness succeeds.
The focused Client regression and the full Signal scenario cover this change.

`SYSTEM-TOPOLOGY-01/02/03` now pass. The accepted target survives Runtime
and whole-Jido replacement, and Controller cleanup stops owned added Agents.
The accepted Agent checkpoints retain their identities. Explicit target
deletion and fresh-BEAM target reconstruction remain outside these probes.

The full-Jido probe holds the parent supervisor until the killed tree releases
its registered names. This isolates durable target recovery from the
immediate-restart race. The separate `SYSTEM-SUPERVISION-01` probe now passes
with a bounded wait for old named children, but that local fix still needs
review and repeated runs. `SYSTEM-BEDROCK-01` failed unassisted placeholder
shutdown and `SYSTEM-BEDROCK-02` passed with Bedrock 0.7.2 before the real
Bedrock service suite was paused by user direction.
The peer probe retains the absent exclusive-owner contract
(`SYSTEM-CLUSTER-01`) without changing the approved core DIST-03 skip. It is
skipped by user direction because cluster-exclusive ownership is outside the
V3 beta scope. Its source remains, but `mix test.all` and CI do not run it.
The JSON/Flow/Directive journey's `SYSTEM-BUS-01` timeout did not recur in
the latest full run with nonblocking Client delivery. Keep it enabled
and repeat it before closing the timing failure.

One Redis Bus-replacement run also timed out while waiting for Controller
readiness. Ten focused runs with seeds 1 through 10, then runs with seeds 0, 7
and 19, passed with the same
readiness call and timeout. The cause is not established. The test stays enabled
and now reports Controller status and component errors if readiness fails.
An included-team replacement also timed out on ETS in an earlier run; that path
did not capture component errors. The latest run passed. Do not count one
passing repeat as proof that either timing failure is fixed.

## Focused runs and longer repetition

```sh
mix test test/system/runtime/agents_test.exs --only adapter:ets --seed 0
mix test test/system/runtime/topology_test.exs --only adapter:file --seed 0
mix test test/system/services/redis_test.exs --only scenario:bus_recovery --seed 0
mix test test/system/services/bedrock_restart_test.exs --only service --seed 0
```

Do not combine a narrow `--only` selection with `--include system` or
`--include service`: ExUnit combines include filters with OR. Choose the entry
file to restrict the service, then use one filter to restrict the scenario.

For a longer seeded run, reuse the model scenarios and full-BEAM reconstruction:

```sh
elixir test/system/burn_in.exs --runs 5 --rounds 100 --seed 93
```

Each run starts a new Mix/BEAM process, increments the seed, and stops on the
first failure. Each adapter runs one independent model sequence; the peer case
adds three full BEAM crashes and required restores. The model checks exact
state, revisions, empty Agent mailboxes, an empty Agent pool, exact record growth,
bounded stored bytes, and process/memory growth. Memory bounds allow observer
history and VM allocation; they are leak guards, not performance benchmarks.

The normal model suite uses seeds 17, 93 and 8191 with two rounds. Select one
seed with `JIDO_SYSTEM_MODEL_SEED`, or 1..1000 rounds with
`JIDO_SYSTEM_MODEL_ROUNDS`. Failures retain the original command list before
bounded reduction starts, then save the shorter replay when reduction ends.
Every run also writes the compact system report. This focused burn-in does not
run all enabled research probes; a green burn-in is not a green `mix test.all`.
