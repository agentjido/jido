# Bedrock and Raft Storage

This guide stores Jido records in a Bedrock cluster, a distributed key-value store that runs inside your Elixir application. Jido talks to Bedrock through `Jido.Persistence.Bedrock`.

Jido has no separate Raft adapter. Raft appears here only because Bedrock uses the `bedrock_raft` package, and you add that package as a dependency. To run your own Raft log, write a [custom adapter](custom-persistence-adapter.md) that gives one atomic conditional write per key.

This adapter has a narrower test record than the others. Jido's test suite exercises it against a local stand-in for the repository, and its service suite against a live cluster is currently paused. Test your own cluster setup before you rely on it, including the failure cases below.

The code here needs a running cluster, so the examples are fragments.

## Add the dependencies

Bedrock is optional for Jido. The adapter supports Bedrock `0.7.2` and later `0.7.x`, with Bedrock Raft `0.10.x`.

<!-- partial -->
```elixir
defp deps do
  [
    {:jido, github: "agentjido/jido", branch: "migration/consolidated-v3"},
    {:bedrock, "~> 0.7.2"},
    {:bedrock_raft, "~> 0.10.0"}
  ]
end
```

With either package missing, or at another version, validation returns an error that names the requirement.

## Define the cluster and repository

The host application owns the cluster and supervises it. Bedrock's own documentation covers cluster configuration.

<!-- partial -->
```elixir
defmodule MyApp.Cluster do
  use Bedrock.Cluster, otp_app: :my_app, name: "my_app"
end

defmodule MyApp.Repo do
  use Bedrock.Repo, cluster: MyApp.Cluster
end
```

## Configure an instance

<!-- partial -->
```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary",
    persistence: {Jido.Persistence.Bedrock, repo: MyApp.Repo}
end
```

Start the cluster before the instance. A persistent Agent cannot start without the namespace.

| Option | Default | Meaning |
| --- | --- | --- |
| `:repo` | Required | A loaded module created with `use Bedrock.Repo` |
| `:prefix` | `"jido:persistence:"` | A non-empty binary below `<<0xFF>>`, prepended to each key |
| `:timeout_in_ms` | `5_000` | A positive integer or `:infinity`, for each transaction |

An unknown or repeated option fails validation.

## Size limits

Bedrock accepts keys of at most 16 KiB and values of at most 128 KiB. The adapter checks both before a transaction starts:

| Limit exceeded | Result |
| --- | --- |
| Key plus prefix over 16,384 bytes | `{:error, {:rejected, {:bedrock_key_too_large, size, 16_384}}}` |
| Value over 131,072 bytes | `{:error, {:rejected, {:bedrock_value_too_large, size, 131_072}}}` |
| Key in the system keyspace | `{:error, {:rejected, :bedrock_system_key_not_allowed}}` |

The value limit matters for Jido. A record holds the complete Agent, including its definition and state, and a [Flow execution record](flow-continuations.md) holds one step's values. A write over the limit is a certain failure, but it still fails the Turn. Measure your largest Agent before you choose this adapter. Keep large documents outside Agent state.

## Write behavior

A conditional write is one Bedrock transaction. It reads the key, compares the exact bytes, and writes the new bytes. `Repo.get/1` inside the transaction adds a read conflict, so a concurrent writer causes an abort.

Bedrock retries commit failures by default, and a commit timeout can have an unknown result. A retry could then see the value from its own first attempt and report a false conflict. The adapter sets `retry_limit: 0` on every write transaction to keep results exact:

| Outcome | Result |
| --- | --- |
| Committed | `:ok` |
| The compared value differs | `{:error, :conflict}` |
| A resolver abort | `{:error, :conflict}` |
| Any other transaction failure | `{:error, {:indeterminate, reason}}` |

After an indeterminate result, read before you decide what to do. See [Recovery Limits](../durability/recovery-and-effect-limits.md).

Each transaction runs in a fresh process. A write therefore does not join a Bedrock transaction your application has open. It commits on its own, and your transaction cannot roll it back.

## Durability

The adapter does not make a relaxed cluster durable. Bedrock's cluster configuration decides the durability profile, and Bedrock acknowledges a commit after every required log has appended and synced its write-ahead log. Use Bedrock's strict durability mode in production. Its default is `:strict`, and setting `durability_mode: :relaxed` on the cluster weakens what `:ok` means.

## Related

- [Storage Model](persistence-storage-model.md): records, conditions, and write results.
- [Persistence Adapters](persistence-adapters.livemd): compare the shipped adapters.
- [Custom Adapters](custom-persistence-adapter.md): implement another store.
