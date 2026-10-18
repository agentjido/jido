# System verification

These tests check the current AgentServer contract with real storage, explicit
fault barriers, and process monitors. They check saved state, effects, revisions,
and resource cleanup. They do not use the removed Topology controller or Plugin
commit projection API.

```sh
mix test.persistence
mix test.system
mix test.all --warnings-as-errors
mix test.services
python3 test/system/run_s3_minio_local.py test/system/services/minio
```

`mix test.all` includes local system tests. It does not start Redis, PostgreSQL,
or MinIO. Service tests run only when selected. A missing service prerequisite
fails setup.

## Current checks

- ETS, File, and SQLite: create, restore, revision conflicts, tombstones,
  cancellation, deadlines, uncertain writes, and recoverable delivery.
- File: corrupt records, write and delete failures, and recovery after BEAM loss.
- Runtime: supervisor replacement, queue limits, Bus replacement, signal replay,
  current turn telemetry, host metrics, and OpenTelemetry export.
- Load: repeated Agent definition and Codec operations, and complete activation
  cleanup after mixed Server workloads.
- Redis and PostgreSQL: shared storage contracts and service fault checks.
- S3/MinIO: shared storage contracts, conditional write races, and lost replies.

The cluster ownership probe and the Bedrock service probes retain their existing
skips. These tests do not establish distributed ownership or Bedrock durability.
No new skips were added during the API update.

## Service setup

Redis needs `redis-server` on PATH. To select an executable, set
`JIDO_SYSTEM_REDIS_SERVER`. The fixture starts its own process and removes its
socket and files. It does not connect to an existing Redis service.

PostgreSQL needs Docker and a cached `postgres:17-alpine` image. To select another
local image, set `JIDO_SYSTEM_POSTGRES_IMAGE`. The fixture uses `--pull=never`
and removes only its own container.

The Python MinIO runner starts and stops its own temporary service. To use a
separate test service instead:

```sh
JIDO_SYSTEM_MINIO_URL=http://127.0.0.1:9000 \
JIDO_SYSTEM_MINIO_ACCESS_KEY=your-test-access-key \
JIDO_SYSTEM_MINIO_SECRET_KEY=your-test-secret-key \
mix test.services.minio
```

Use test credentials with bucket create, list, get, put, and delete rights.
The fixture removes only its own randomly named bucket. It does not use ambient
AWS credentials. Direct S3 requests need conditional PUT support and SHA-256
checksums on GET.

## Fault controls and evidence

Use explicit barriers and process monitors. Do not use sleeps or polling to
order mutations. A caller wait timeout does not cancel an accepted turn.
An asynchronous persistence worker owns the write barrier. Terminate the full
activation to test activation loss; the supervisor can replace a failed worker.

The independent turn model uses `JIDO_SYSTEM_MODEL_SEED` and
`JIDO_SYSTEM_MODEL_ROUNDS`. Reports are stored in ignored `tmp/system-runs`.

[SCENARIOS.md](SCENARIOS.md) records the current checks.
[TODO.md](TODO.md) retains historical evidence and open research probes.
