# Storage adapter conformance

`Jido.Storage` defines six callbacks for checkpoints and thread journals. The
shared ExUnit suites make those callback semantics executable for built-in and
third-party adapters.

## Shared contract

| Area | Required behavior |
| --- | --- |
| Checkpoint reads | Return `{:ok, value}` when present and `:not_found` when absent. |
| Checkpoint writes | Preserve arbitrary terms and overwrite the same key. |
| Checkpoint deletes | Remove the value and remain idempotent. |
| Thread reads | Reconstruct ordered entries, metadata, revision, timestamps, and stats; return `:not_found` when there are no entries. |
| Thread appends | Accept entry structs or maps, preserve existing entries, assign contiguous zero-based sequences, increment revision by appended count, and preserve creation metadata. |
| Optimistic writes | Accept a matching `:expected_rev`; reject a stale value with `{:error, :conflict}` without changing the journal. Revision `0` is valid for a new thread. |
| Thread deletes | Remove entries and metadata and remain idempotent. |

Use `JidoTest.StorageCheckpointConformance` and
`JidoTest.StorageThreadConformance` from `test/support`. Each adapter supplies
an option expression that creates isolated storage for every generated test.
For example:

```elixir
use JidoTest.StorageThreadConformance,
  adapter: MyStorage,
  setup: quote(do: [namespace: unique_namespace()])
```

The Jido test suite runs both contracts against ETS and File. External adapters
should import the helpers from an exact Jido commit and run them against every
supported backend.

## Adapter-specific coverage

The shared suites intentionally do not prescribe implementation details.
Adapters retain their own tests for concerns such as:

- process and table lifecycle;
- filesystem safety and corrupt persisted state;
- repository configuration and transaction failures;
- backend-specific locking, retry, and concurrency behavior.

Concurrent adapters should additionally prove that parallel appends are
lossless with unique contiguous sequences, and that two writers using the same
`expected_rev` produce one success and one conflict.

## Validation

Run the built-in adapters with:

```sh
mix test test/jido/storage
```

An adapter is conformant only when its shared suite and applicable
adapter-specific tests pass.
