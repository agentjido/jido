# Local Stores

This guide covers the three adapters that need no external service: ETS for tests and development, files for one BEAM instance, and Mnesia for an application that already owns a Mnesia setup.

| Adapter | Options | Data ends when | Use it for |
| --- | --- | --- | --- |
| `Jido.Persistence.ETS` | `:table` | The BEAM stops | Tests, development, examples |
| `Jido.Persistence.File` | `:path` (required) | You delete the files | One node with a local disk |
| `Jido.Persistence.Mnesia` | `:table` (required) | Your table copies say so | Applications that manage Mnesia |

Each example uses this Agent:

```elixir
defmodule LocalStoresGuide.Ticket do
  use Jido.Agent, name: "local_stores_guide_ticket"

  state do
    schema Jido.Joi.object(%{status: Jido.Joi.string() |> Jido.Joi.default("open")})
  end
end

ticket = LocalStoresGuide.Ticket.instantiate!(id: "ticket-1001")
```

## ETS

`Jido.Persistence.ETS` keeps records in a named, public ETS table that it creates on first use.

```elixir
ets_store = {Jido.Persistence.ETS, table: :local_stores_guide_tickets}

:ok = Jido.Persistence.save_agent(ets_store, ticket, namespace: "support")

{:ok, %{id: "ticket-1001"}, 0} =
  Jido.Persistence.load_agent_with_revision(
    ets_store,
    LocalStoresGuide.Ticket,
    "ticket-1001",
    namespace: "support"
  )
```

- `:table` is an atom that selects the base table name. It defaults to `:jido_persistence`. The actual table is named with a `_records` suffix.
- With the Jido application running, the table survives the exit of the process that created it, because a supervised process inherits it.
- Without the Jido application, the table ends with its creator.
- All data ends when the BEAM stops.

Give each test its own table name so tests can run concurrently:

```elixir
table = :"tickets_test_#{System.unique_integer([:positive])}"
persistence = {Jido.Persistence.ETS, table: table}
```

ETS does not recover an Agent across a restart of the node. Do not use it where you need durability.

## Files

`Jido.Persistence.File` writes one file per key under `<path>/records/`. The file name is a hash of the key.

```elixir
path = Path.join(System.tmp_dir!(), "local-stores-guide-#{System.unique_integer([:positive])}")
file_store = {Jido.Persistence.File, path: path}

:ok = Jido.Persistence.save_agent(file_store, ticket, namespace: "support")

{:ok, %{id: "ticket-1001"}} =
  Jido.Persistence.load_agent(file_store, LocalStoresGuide.Ticket, "ticket-1001", namespace: "support")

[record_file] = Path.wildcard(Path.join(path, "records/*.bin"))
true = String.ends_with?(record_file, ".bin")

File.rm_rf!(path)
```

Each write goes to a temporary file and then renames it over the record. A
small `.key` sidecar verifies the hashed file name. A bounded, fixed-depth hash
radix index under `<path>/scan_index/` supports optional paged scan and JSONL
export. Writes and deletes for one key share a lock inside the local BEAM.

With `Jido.Persistence.Codec.JSON`, each `.bin` file is a valid tagged JSON
document that normal JSON tools can parse. The default Term codec is smaller.

That lock is the limit of this adapter:

- One BEAM instance must own the directory. Separate OS processes or BEAM instances must not write to it at the same time, because the lock does not cross them and the conditional write can then lose a race.
- All callers must use the same path, with no alternate symbolic links.
- The adapter does not call `fsync`. A power loss or OS crash can lose a recent write that already returned `:ok`.

For storage shared across BEAM instances, use [Ecto on PostgreSQL](ecto-persistence.md), [Redis or S3](redis-and-s3-persistence.md), or [Bedrock](bedrock-persistence.md).

## Mnesia

`Jido.Persistence.Mnesia` uses a table that your application owns. Jido does not start Mnesia, create the schema or table, or choose copies. It requires a `set` table with attributes `[:key, :value]`. A `local_content` table is not supported.

Add `:mnesia` to your application's `extra_applications`:

<!-- partial -->
```elixir
def application do
  [mod: {MyApp.Application, []}, extra_applications: [:logger, :mnesia]]
end
```

Then start Mnesia and create the table before you start a Jido instance that uses it. This example uses a RAM copy:

```elixir
{:ok, _started} = Application.ensure_all_started(:mnesia)

{:atomic, :ok} =
  :mnesia.create_table(:local_stores_guide_records,
    attributes: [:key, :value],
    ram_copies: [node()]
  )

mnesia_store = {Jido.Persistence.Mnesia, table: :local_stores_guide_records}

{:ok, ^mnesia_store} = Jido.Persistence.resolve_config(mnesia_store, nil)

:ok = Jido.Persistence.save_agent(mnesia_store, ticket, namespace: "support")

{:ok, %{id: "ticket-1001"}} =
  Jido.Persistence.load_agent(mnesia_store, LocalStoresGuide.Ticket, "ticket-1001", namespace: "support")
```

For records that survive a restart, create the schema on disk and use `disc_copies`. Your application also owns replicas and recovery after a partition. Jido adds no policy on top:

<!-- partial -->
```elixir
:ok = :mnesia.create_schema([node()])
{:ok, _started} = Application.ensure_all_started(:mnesia)

{:atomic, :ok} =
  :mnesia.create_table(:my_app_jido_records,
    attributes: [:key, :value],
    disc_copies: [node()]
  )

:ok = :mnesia.wait_for_tables([:my_app_jido_records], 5_000)
```

Each read and write runs in its own Mnesia transaction. A conditional write takes a write lock on the key and commits the comparison and replacement together.

Three behaviors matter in application code:

- `:table` must be the only option. Validation inspects the table and waits up to 5 seconds for it on each operation, and an unusable table fails with `{:error, {:invalid_persistence_options, Jido.Persistence.Mnesia, reason}}`.
- The adapter rejects a call made from inside your own Mnesia transaction, so a save cannot join your transaction:

  ```elixir
  {:atomic, {:error, {:rejected, :nested_transaction}}} =
    :mnesia.transaction(fn ->
      Jido.Persistence.Mnesia.compare_and_swap("key", :not_found, "value", table: :local_stores_guide_records)
    end)
  ```

- An aborted write transaction returns `{:error, {:mnesia_aborted, reason}}` from the adapter, which `Jido.Persistence.Store` treats as indeterminate. Reload before you retry.

## Related

- Persistence Adapters: configure a store on an instance.
- [Storage Model](persistence-storage-model.md): what these adapters store.
- Test Jido Systems: test patterns for persistent Agents.
