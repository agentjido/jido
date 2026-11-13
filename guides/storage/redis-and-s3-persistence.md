# Redis and S3 Stores

This guide configures the two adapters that reach an external service through a function you supply. Jido does not ship a Redis or S3 client. Your application owns the connection, credentials, and pooling, and gives the adapter one function for sending a command or request.

| Adapter | Supplied function | Use it for |
| --- | --- | --- |
| `Jido.Persistence.Redis` | `:command_fn`, which runs one Redis command | Shared storage with frequent writes, if your Redis setup is durable enough |
| `Jido.Persistence.S3` | `:request_fn`, which signs and sends one request | Low-frequency records in object storage |

Both follow the contract in [Storage Model](persistence-storage-model.md): a lost reply to a write must be reported as uncertain, never retried inside the function.

The real client examples here need a running service, so they are fragments. Each section then gives an in-memory stand-in that runs with no service, for your own tests.

## Redis

### Connect a client

`:command_fn` takes a list of binaries and returns the client's reply. This example uses Redix, which you add to your own application:

<!-- partial -->
```elixir
defmodule MyApp.JidoRedis do
  def command(command), do: Redix.command(:jido_redis, command, timeout: 5_000)
end

defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary",
    persistence: {Jido.Persistence.Redis, command_fn: &MyApp.JidoRedis.command/1, prefix: "my-app"}
end
```

Start the connection before the instance:

<!-- partial -->
```elixir
children = [
  {Redix, name: :jido_redis, host: "redis.internal"},
  MyApp.Jido
]
```

The function must return these shapes:

| Command | Reply |
| --- | --- |
| `["GET", key]` | `{:ok, value}`, or `{:ok, nil}` for a missing key |
| `["EVAL", script, "1", key, mode, previous, value]` | `{:ok, 1}` when written, `{:ok, 0}` on a failed comparison |
| `["SET", key, value]` | `{:ok, "OK"}` |
| `["DEL", key]` | `{:ok, count}` |
| Any failure | `{:error, reason}` |

### Options

| Option | Default | Meaning |
| --- | --- | --- |
| `:command_fn` | Required | A function of one argument |
| `:prefix` | `"jido"` | Each Redis key is `"<prefix>:<key>"` |

Conditional writes run one Lua `EVAL` that compares and replaces the value, so the connection must permit `EVAL`. A `{:error, reason}` reply to `EVAL` becomes `{:error, {:indeterminate, reason}}`, because the script may have run.

### Do not expire durable keys

The adapter has no TTL option. Jido does not expire persistence records
automatically. Configure Redis so eviction does not remove these keys. An
evicted Agent record, tombstone, Flow record, or wake record can break restore
or remove a stale-writer fence. Jido has only the durability that your Redis
persistence, replication, and eviction settings provide.

### Test without a server

This stand-in handles `GET`, `EVAL`, and `DEL`, which is what `Jido.Persistence` and Flow cleanup use. It runs a conditional write as one step, as the Lua script does.

```elixir
defmodule RedisGuide.FakeRedis do
  def start_link, do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def command(["GET", key]), do: {:ok, Agent.get(__MODULE__, &Map.get(&1, key))}

  def command(["EVAL", _script, "1", key, mode, previous, value]) do
    Agent.get_and_update(__MODULE__, fn data ->
      current = Map.get(data, key)
      matched? = if mode == "missing", do: is_nil(current), else: current == previous

      if matched?, do: {{:ok, 1}, Map.put(data, key, value)}, else: {{:ok, 0}, data}
    end)
  end

  def command(["DEL", key]) do
    Agent.update(__MODULE__, &Map.delete(&1, key))
    {:ok, 1}
  end

  def keys, do: Agent.get(__MODULE__, &Map.keys/1)
end

defmodule RedisGuide.Session do
  use Jido.Agent, name: "redis_guide_session"

  state do
    schema Jido.Joi.object(%{cart_items: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end
end

{:ok, _pid} = RedisGuide.FakeRedis.start_link()

redis_store =
  {Jido.Persistence.Redis, command_fn: &RedisGuide.FakeRedis.command/1, prefix: "shop"}

session = RedisGuide.Session.instantiate!(id: "session-1", state: %{cart_items: 2})

:ok = Jido.Persistence.save_agent(redis_store, session, namespace: "shop")

{:ok, %{state: %{cart_items: 2}}, 0} =
  Jido.Persistence.load_agent_with_revision(redis_store, RedisGuide.Session, "session-1",
    namespace: "shop"
  )

["shop:" <> _encoded_key] = RedisGuide.FakeRedis.keys()
```

A stand-in checks your wiring and failure handling. It cannot prove anything about a real Redis server.

## S3

`Jido.Persistence.S3` stores each record as one object with conditional writes. It is for low-frequency records. A durable Flow writes several keys per step, and each write is one request.

### Supply a request function

`:request_fn` receives one map and sends one request:

| Field | Meaning |
| --- | --- |
| `:method` | `:get`, `:put`, or `:delete` |
| `:bucket`, `:key` | The target object |
| `:headers` | A map to send as given, including conditional and checksum headers |
| `:body` | The value for `:put`, otherwise `nil` |
| `:timeout_ms` | The time limit your client must honor |
| `:retry`, `:follow_redirects` | Always `false`. Your client must not retry writes or follow redirects |

It returns `{:ok, %{status: integer, headers: map_or_list, body: binary, code: string_or_nil}}` or `{:error, reason}`. `:code` is the parsed S3 error code, such as `"NoSuchKey"`. The adapter needs it to tell a missing object from a missing bucket. Header names are case insensitive.

This function uses ExAws, which you add to your own application. Add your region and endpoint to `config`:

<!-- partial -->
```elixir
defmodule MyApp.JidoS3 do
  def request(request) do
    operation = %ExAws.Operation.S3{
      http_method: request.method,
      bucket: request.bucket,
      path: request.key,
      headers: request.headers,
      body: request.body || ""
    }

    config = [
      retries: [max_attempts: 1, client_error_max_attempts: 1],
      http_opts: [recv_timeout: request.timeout_ms, follow_redirect: false]
    ]

    case ExAws.request(operation, config) do
      {:ok, %{status_code: status, headers: headers, body: body}} ->
        {:ok, %{status: status, headers: headers, body: body}}

      {:error, {:http_error, status, %{body: body, headers: headers}}} ->
        {:ok, %{status: status, code: error_code(body), headers: headers, body: body}}

      {:error, _reason} ->
        {:error, {:indeterminate, :request_failed}}
    end
  end

  defp error_code(body) do
    case Regex.run(~r/<Code>([^<]+)<\/Code>/, body) do
      [_match, code] -> code
      _other -> nil
    end
  end
end

defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary",
    persistence:
      {Jido.Persistence.S3,
       bucket: "my-app-agents", prefix: "jido/", request_fn: &MyApp.JidoS3.request/1}
end
```

Report a lost write reply as `{:error, {:indeterminate, reason}}`. Use `{:error, {:rejected, reason}}` only when you know no request reached S3. Any other `{:error, reason}` on a write counts as indeterminate.

Keep credentials, object bodies, ETags, and signed headers out of your logs and telemetry. After an indeterminate result, do not switch to another endpoint or replica.

### Options and limits

| Option | Default | Meaning |
| --- | --- | --- |
| `:bucket` | Required | A non-empty string |
| `:request_fn` | Required | A function of one argument |
| `:prefix` | `"jido/"` | Prepended to each object key |
| `:timeout_ms` | `5_000` | Per request, up to `120_000`. The adapter runs each request in its own process and stops it at this limit |

Other options fail validation. An object can hold at most 5,000,000 bytes. A larger write returns `{:error, {:rejected, :object_too_large}}` before any request. An object key can have at most 1,024 bytes. Object keys are the prefix, then `k_`, then the unpadded URL-safe Base64 of the storage key.

### What the bucket must support

- Conditional `PUT` with `If-Match` and `If-None-Match: *`. The adapter creates with `If-None-Match: *` and updates with `If-Match` on the ETag from its read.
- Consistent reads, so that a read returns the latest confirmed write.
- SHA-256 checksums returned as `x-amz-checksum-sha256`. Every write sends this header, and every read asks for it and verifies it. A read fails with `{:error, :missing_checksum}` or `{:error, :checksum_mismatch}` otherwise.

`412 PreconditionFailed` and `409 ConditionalRequestConflict` on a conditional write mean `{:error, :conflict}`. A `403` or other status on a write is indeterminate. On a read, a `403` returns `{:error, :access_denied}` and a `404` with `NoSuchBucket` returns `{:error, :missing_bucket}`.

The adapter's `delete/2` is for maintenance and Flow cleanup. In a versioned bucket it can create a delete marker, and older versions can remain. Do not run maintenance deletes against a key that a writer can still use. Agent deletion writes a [tombstone](../durability/deletion-and-tombstones.md) and does not call `delete/2`.

### Test without a server

This stand-in follows the response shapes above, including checksums and conditional headers. It omits `:delete`, which only Flow cleanup and maintenance use:

```elixir
defmodule S3Guide.FakeS3 do
  def start_link, do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def request(%{method: :get, key: key}) do
    case Agent.get(__MODULE__, &Map.get(&1, key)) do
      nil ->
        {:ok, %{status: 404, code: "NoSuchKey", headers: [], body: ""}}

      {body, etag} ->
        checksum = :crypto.hash(:sha256, body) |> Base.encode64()
        headers = [{"ETag", etag}, {"x-amz-checksum-sha256", checksum}]
        {:ok, %{status: 200, code: nil, headers: headers, body: body}}
    end
  end

  def request(%{method: :put, key: key, headers: headers, body: body}) do
    Agent.get_and_update(__MODULE__, fn objects ->
      current = Map.get(objects, key)

      if allowed?(current, headers) do
        etag = :crypto.hash(:md5, body) |> Base.encode16()
        {{:ok, %{status: 200, code: nil, headers: [], body: ""}}, Map.put(objects, key, {body, etag})}
      else
        {{:ok, %{status: 412, code: "PreconditionFailed", headers: [], body: ""}}, objects}
      end
    end)
  end

  defp allowed?(current, %{"if-none-match" => "*"}), do: is_nil(current)
  defp allowed?({_body, etag}, %{"if-match" => etag}), do: true
  defp allowed?(_current, _headers), do: false
end

defmodule S3Guide.Report do
  use Jido.Agent, name: "s3_guide_report"

  state do
    schema Jido.Joi.object(%{title: Jido.Joi.string() |> Jido.Joi.default("")})
  end
end

{:ok, _pid} = S3Guide.FakeS3.start_link()

s3_store = {Jido.Persistence.S3, bucket: "reports", request_fn: &S3Guide.FakeS3.request/1}

report = S3Guide.Report.instantiate!(id: "report-1", state: %{title: "Q3"})
revised = %{report | state: %{title: "Q3 revised"}}

:ok = Jido.Persistence.save_agent(s3_store, report, namespace: "reports")

:ok =
  Jido.Persistence.save_agent(s3_store, revised,
    namespace: "reports",
    revision: 1,
    expected_revision: 0
  )

{:ok, %{state: %{title: "Q3 revised"}}, 1} =
  Jido.Persistence.load_agent_with_revision(s3_store, S3Guide.Report, "report-1",
    namespace: "reports"
  )
```

## Related

- [Storage Model](persistence-storage-model.md): conditions and write results.
- Custom Adapters: when neither function shape fits your service.
- Continuation Storage: the write load of durable Flows.
