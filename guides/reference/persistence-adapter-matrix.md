# Persistence Matrix

This guide compares the seven `Jido.Persistence.Store` adapters that Jido includes. Use it to choose an adapter, then follow the link for setup. For what each layer writes, see [Storage Model](../storage/persistence-storage-model.md).

## Compare the adapters

| Adapter | Data survives | Shared across nodes | Atomic write | Value limit | Host supplies | Guide |
| --- | --- | --- | --- | --- | --- | --- |
| `Jido.Persistence.ETS` | Until the BEAM stops | No | ETS `insert_new` or `select_replace` | None | Nothing | [Local Stores](../storage/local-persistence-adapters.md) |
| `Jido.Persistence.File` | Until you delete the files | No. One BEAM must own the directory. | A lock in the BEAM, then a temporary file and rename | None | A directory | [Local Stores](../storage/local-persistence-adapters.md) |
| `Jido.Persistence.Mnesia` | As your table copies define | As your table copies define | A Mnesia transaction with a write lock | None | A running Mnesia and a `set` table with attributes `[:key, :value]` | [Local Stores](../storage/local-persistence-adapters.md) |
| `Jido.Persistence.Ecto` | As your database defines | Yes | One `INSERT`, or one conditional `UPDATE` | None | A running repo and a migrated table. PostgreSQL or SQLite only. | [Ecto Storage](../storage/ecto-persistence.md) |
| `Jido.Persistence.Redis` | As your Redis defines. `:ttl` expires keys. | Yes | One Lua `EVAL` | None | `:command_fn`, which runs one command. The connection must permit `EVAL`. | [Redis and S3 Stores](../storage/redis-and-s3-persistence.md) |
| `Jido.Persistence.S3` | As your bucket defines | Yes | A conditional `PUT` with an ETag token | 5,000,000 bytes | `:request_fn`, which signs and sends one request | [Redis and S3 Stores](../storage/redis-and-s3-persistence.md) |
| `Jido.Persistence.Bedrock` | As your cluster's durability mode defines | Yes | One Bedrock transaction | Value 128 KiB. Key plus prefix 16 KiB. | A supervised cluster and a module with `use Bedrock.Repo` | [Bedrock and Raft Storage](../storage/bedrock-persistence.md) |

"Data survives" and "Shared" state the adapter's limit. The system you connect to sets the real guarantee. An adapter cannot make a relaxed database, a Redis without persistence, or a relaxed Bedrock cluster durable.

Jido includes only these seven. Raft support comes through Bedrock, which uses Bedrock Raft. To target another store, write a [custom adapter](../storage/custom-persistence-adapter.md).

## Choose by need

| Need | Use |
| --- | --- |
| Tests, examples, and development | `Jido.Persistence.ETS` |
| One node with a local disk | `Jido.Persistence.File` |
| An application that already runs Mnesia | `Jido.Persistence.Mnesia` |
| A SQL database you already run | `Jido.Persistence.Ecto` |
| Several BEAM nodes with frequent writes | `Jido.Persistence.Ecto`, `Jido.Persistence.Redis`, or `Jido.Persistence.Bedrock` |
| Low-frequency records in object storage | `Jido.Persistence.S3` |

This guide makes no throughput claim. Measure with your own record sizes, as [Load Testing](../operations/load-and-performance-testing.md) describes.

## Options

`Jido.Persistence.Store.open/1` validates a configuration. An instance does this at startup.

| Adapter | Option | Default | Meaning |
| --- | --- | --- | --- |
| ETS | `:table` | `:jido_persistence` | The base table name, an atom. |
| File | `:path` | Required | The base directory, a nonempty string. |
| Mnesia | `:table` | Required | An existing table. No other option is accepted. |
| Ecto | `:repo` | Required | A running repo with a PostgreSQL or SQLite adapter. |
| Ecto | `:schema` | `Jido.Persistence.Ecto.Record` | A schema with exactly `:key`, `:value`, and `:write_token`. |
| Ecto | `:repo_options` | `[]` | Options for repo calls, such as `:prefix` and `:timeout`. It rejects `:on_conflict` and `:conflict_target`. |
| Redis | `:command_fn` | Required | A one-argument function. |
| Redis | `:prefix` | `"jido"` | Each key is `"<prefix>:<key>"`. |
| Redis | `:ttl` | None | The key lifetime in milliseconds, a positive integer. |
| S3 | `:bucket` | Required | A nonempty string. |
| S3 | `:request_fn` | Required | A one-argument function. |
| S3 | `:prefix` | `"jido/"` | A string prepended to each object key. |
| S3 | `:timeout_ms` | `5_000` | Per request, at most `120_000`. |
| Bedrock | `:repo` | Required | A loaded module with `use Bedrock.Repo`. |
| Bedrock | `:prefix` | `"jido:persistence:"` | A nonempty binary below the system keyspace. |
| Bedrock | `:timeout_in_ms` | `5_000` | A positive integer or `:infinity`, per transaction. |

Ecto, S3, and Bedrock reject unknown options. Mnesia accepts `:table` alone. ETS, File, and Redis ignore other keys.

```elixir
alias Jido.Persistence.Store

{:ok, {Jido.Persistence.ETS, []}} = Store.open(Jido.Persistence.ETS)
{:ok, {Jido.Persistence.ETS, [table: :matrix_guide]}} = Store.open({Jido.Persistence.ETS, table: :matrix_guide})

{:error, {:invalid_persistence_options, Jido.Persistence.File, ":path must be a non-empty string"}} =
  Store.open({Jido.Persistence.File, []})

{:error, {:invalid_persistence_options, Jido.Persistence.S3, :unknown_option}} =
  Store.open({Jido.Persistence.S3, bucket: "agents", request_fn: fn _request -> :ok end, region: "eu"})

{:error, :persistence_not_configured} = Store.open(nil)
```

## Optional dependencies

| Adapter | Add to your `deps` | Without it |
| --- | --- | --- |
| ETS, File, Mnesia | Nothing. Add `:mnesia` to `extra_applications` for Mnesia. | Not applicable |
| Ecto | `:ecto_sql` and a driver, before Jido compiles | `Jido.Persistence.Ecto` reports invalid configuration |
| Redis | A Redis client of your choice, called from `:command_fn` | Not applicable |
| S3 | An HTTP client and an AWS signer of your choice, called from `:request_fn` | Not applicable |
| Bedrock | `{:bedrock, "~> 0.7.2"}` and `{:bedrock_raft, "~> 0.10.0"}` | `Jido.Persistence.Bedrock` reports invalid configuration |

## Callback contract

Each adapter here implements all five `Jido.Persistence.Store` callbacks. A custom adapter must implement `c:Jido.Persistence.Store.get/2` and `c:Jido.Persistence.Store.compare_and_swap/4`. Without `c:Jido.Persistence.Store.delete/2`, Flow execution records remain after each Flow Turn.

| Callback | ETS | File | Mnesia | Ecto | Redis | S3 | Bedrock |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `get/2` returns a read token | No | No | No | No | No | Yes, an ETag | No |
| `compare_and_swap/4` compares | Bytes | Bytes | Bytes | Bytes | Bytes | ETag | Bytes |
| Maintenance `put/3` | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Maintenance `delete/2` | Yes | Yes | Yes | Yes | Yes | Yes | Yes |

Each adapter reports write results the same way:

| Result | Meaning |
| --- | --- |
| `:ok` | The write committed. |
| `{:error, :conflict}` | The condition failed, and no write occurred. |
| `{:error, {:rejected, reason}}` | The adapter refused before a write started. |
| `{:error, {:indeterminate, reason}}` | The write may or may not have committed. Reload before any retry. |

```elixir
store = {Jido.Persistence.ETS, table: :matrix_guide}

:ok = Jido.Persistence.Store.compare_and_swap(store, "invoice-1", :not_found, "draft")
{:ok, "draft", "draft"} = Jido.Persistence.Store.read(store, "invoice-1")
:ok = Jido.Persistence.Store.compare_and_swap(store, "invoice-1", "draft", "sent")
{:error, :conflict} = Jido.Persistence.Store.compare_and_swap(store, "invoice-1", "draft", "paid")
```

## Limits that affect Flows

A durable Flow writes several keys per step through the same adapter, one value for each batch or produced value. These facts affect your choice. See [Continuation Storage](../storage/flow-continuations.md).

- `Jido.Persistence.Bedrock` and `Jido.Persistence.S3` apply their limits to each value, so a large step result can fail. Pass a reference to a large payload through a Flow.
- `Jido.Persistence.S3` makes at least one request per write, and its documents describe it as for low-frequency records.
- `Jido.Persistence.Redis` with `:ttl` can remove a record that a waiting Flow still needs.

## Related

- [Storage Model](../storage/persistence-storage-model.md)
- [Custom Adapters](../storage/custom-persistence-adapter.md)
- [Revisions and Conflicts](../durability/durable-revisions-and-conflicts.md)
