# Ecto Storage

This guide stores Jido records in a SQL table through your application's Ecto repository. Use it when you already run PostgreSQL, or SQLite for a single node.

`Jido.Persistence.Ecto` supports the PostgreSQL and SQLite Ecto adapters only. It stores opaque bytes in one table, one row per storage key. Your application owns the repository, the database, and the migration.

The code here runs in your application and needs a database, so the examples are fragments.

## Add the dependencies

`:ecto_sql` is optional for Jido, so add it and a driver to your application.

<!-- partial -->
```elixir
defp deps do
  [
    {:jido, github: "mikehostetler/new_jido", branch: "main"},
    {:ecto_sql, "~> 3.14"},
    {:postgrex, "~> 0.19 or ~> 1.0"}
  ]
end
```

Use `{:ecto_sqlite3, "~> 0.24.1"}` in place of `:postgrex` for SQLite. Jido must compile with `:ecto_sql` present. Otherwise `Jido.Persistence.Ecto` rejects its options with an error that says it requires the optional dependency at compile time.

## Create the table

The adapter does not run migrations. Generate a migration in your application and call the versioned helper:

<!-- partial -->
```elixir
defmodule MyApp.Repo.Migrations.CreateJidoPersistenceRecords do
  use Ecto.Migration

  def up, do: Jido.Persistence.Ecto.Migration.up(version: 1)
  def down, do: Jido.Persistence.Ecto.Migration.down(version: 1)
end
```

Always pin `:version`. Without it the helper uses the latest version, and a later Jido release could change what an old migration does. `Jido.Persistence.Ecto.Migration.current_version/0` returns the latest version, which is `1` today.

Version 1 creates `jido_persistence_records` with three binary, non-null columns:

| Column | Purpose |
| --- | --- |
| `key` | Primary key. The binary storage key |
| `value` | The stored bytes |
| `write_token` | Random bytes rewritten on every write. A write of identical bytes still changes a column, so the affected-row count stays reliable |

## Configure an instance

Set the adapter on your Jido module and give it a stable namespace. A persistent Agent cannot start without one.

<!-- partial -->
```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary",
    persistence: {Jido.Persistence.Ecto, repo: MyApp.Repo}
end
```

Start the repository before the instance:

<!-- partial -->
```elixir
children = [
  MyApp.Repo,
  MyApp.Jido
]

Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
```

Then use the instance as you would with any other adapter:

<!-- partial -->
```elixir
{:ok, invoice} =
  Jido.start_agent(MyApp.Jido, MyApp.Invoice, id: "inv-1001", persistence: :inherit)

:ok = Jido.AgentServer.await_ready(invoice)
```

## Adapter options

| Option | Default | Meaning |
| --- | --- | --- |
| `:repo` | Required | A running Ecto repository with a supported SQL adapter |
| `:schema` | `Jido.Persistence.Ecto.Record` | The Ecto schema for the table |
| `:repo_options` | `[]` | A keyword list sent to each repository call, such as `:prefix` or `:timeout`. It cannot set `:on_conflict` or `:conflict_target` |

Any other option fails validation.

## Use another table or prefix

To use another table, add a schema with exactly the required fields, and pass the same table name to the migration helper:

<!-- partial -->
```elixir
defmodule MyApp.BillingAgentRecord do
  use Ecto.Schema

  @primary_key {:key, :binary, autogenerate: false}
  schema "billing_agent_records" do
    field :value, :binary
    field :write_token, :binary
  end
end

defmodule MyApp.Repo.Migrations.CreateBillingAgentRecords do
  use Ecto.Migration

  def up, do: Jido.Persistence.Ecto.Migration.up(version: 1, table: :billing_agent_records)
  def down, do: Jido.Persistence.Ecto.Migration.down(version: 1, table: :billing_agent_records)
end
```

Then select the schema in the adapter declaration:

<!-- partial -->
```elixir
{Jido.Persistence.Ecto, repo: MyApp.Repo, schema: MyApp.BillingAgentRecord}
```

The schema must have `:key` as its single binary primary key, binary `:value` and `:write_token` fields, and no other fields. The database must enforce `NOT NULL` on all three columns.

To use a database prefix, set it in both places. The prefix passed to the migration must match the one the adapter uses:

<!-- partial -->
```elixir
Jido.Persistence.Ecto.Migration.up(version: 1, prefix: "tenant_a")

{Jido.Persistence.Ecto, repo: MyApp.Repo, repo_options: [prefix: "tenant_a"]}
```

## Keep the table plain

A conditional write is one statement. A create is one `INSERT` with `ON CONFLICT DO NOTHING`, and an update is one `UPDATE` filtered on the key and the expected bytes. The affected-row count decides the result: `1` is `:ok`, and `0` is `{:error, :conflict}`.

Anything that changes that count breaks the write check:

- Give the repository's role direct select, insert, update, and delete access to the table.
- Do not add a trigger or rule that hides a row, suppresses a write, or changes `key`, `value`, or `write_token`.

Application tables can stay in the same database. Do not read or join `value` in application code. See [Storage Model](persistence-storage-model.md).

## Transactions

`Jido.AgentServer` writes from its own process, so its saves commit independently of any transaction you have open in another process.

A direct `Jido.Persistence.save_agent/3` call runs in the calling process. Inside your `Repo.transaction/2`, it joins that transaction, and its `:ok` is not final until the transaction commits. If the transaction rolls back, so does the save.

## Failures

| Situation | Result |
| --- | --- |
| Invalid `:repo`, `:schema`, or `:repo_options` | `{:error, {:invalid_persistence_options, Jido.Persistence.Ecto, reason}}` |
| Unsupported Ecto adapter | The same error, with a reason that names the adapter |
| Read fails, including a missing table | `{:error, {:ecto, exception_module, message}}` |
| A database or connection failure during a write | `{:error, {:indeterminate, {:ecto, exception_module, message}}}` |

Validation checks configuration only. It does not query the database, so a missing table appears on the first read or write. A persistent Agent then fails during startup, and `Jido.AgentServer.await_ready/2` exits.

A failed write is uncertain even when the database seems to have rejected it, because the connection can drop after a commit. The runtime stops the activation and a new one reads the stored row. See [Recovery Limits](../durability/recovery-and-effect-limits.md).

## Related

- [Storage Model](persistence-storage-model.md): the records in this table.
- [Production Setup](../operations/production-configuration.md): instance and supervision setup.
- [Continuation Storage](flow-continuations.md): durable Flows add more rows per Turn.
