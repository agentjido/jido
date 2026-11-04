# External service checks

These checks are opt-in. The normal `mix test`, `mix test.ci`, and
`mix test.all` commands must not select the `:service` tag.

Each active check owns its service or creates one unique bucket. It uses only
the test credentials shown here. It removes the owned resource after the test.

## Redis

Prerequisite:

```console
docker pull redis:7-alpine
```

Run:

```console
mix test.services test/external/redis/redis_test.exs
```

The test starts and removes its own container. It publishes Redis only on a
random localhost port.

## PostgreSQL

Prerequisite:

```console
docker pull postgres:17-alpine
```

Run:

```console
mix test.services test/external/postgres/postgres_test.exs
```

The test starts and removes its own container. It uses the database
`jido_system`, user `postgres`, and password `jido-system-only` on a random
localhost port.

## MinIO

Start one dedicated MinIO service with test-only credentials. Set these values
to that exact service:

```console
export JIDO_SYSTEM_MINIO_URL=http://127.0.0.1:9000
export JIDO_SYSTEM_MINIO_ACCESS_KEY=jido-system-only
export JIDO_SYSTEM_MINIO_SECRET_KEY=jido-system-only-secret
mix test.services test/external/minio/minio_test.exs
```

The test creates a random bucket, removes all objects that it wrote, and
removes the bucket. If the three variables are absent, the MinIO tests are
reported as excluded.

## Bedrock

The Bedrock service family is deferred. The current profile records the known
upstream blocker `bedrock-kv/bedrock#319`. Local adapter and transaction tests
remain active in the normal unit suite.

The live AI provider boundary is under `test/external/jido_ai` and uses the
separate `mix test.live` command documented in that directory.
