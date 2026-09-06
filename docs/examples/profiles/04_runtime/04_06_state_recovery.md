# State Recovery

Feature ID: `04_06_state_recovery`. Status: implemented within the tested scope.

## Added feature

A restored Agent retains its complete state, duplicate ledger, and commit revision. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.PersistentCounterRecovery

{:ok, server} = Jido.start_agent(jido, PersistentCounterRecovery,
  id: "counter-1", persistence: {Jido.Persistence.ETS, table: :example_counters}, restore: false)
PersistentCounterRecovery.increment(server, "command-1", 3)
```

## Evidence

5 passing tests with no skips:

- a hibernated counter restores its last durable commit and continues.
- an identical-state commit stores a new revision and restores it.
- required restore reports a missing record.
- a corrupt record prevents restore.
- a stale durable writer cannot replace a newer revision.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_06_state_recovery --seed 0
```

[Source](../../../../examples/04_runtime/04_06_state_recovery/persistent_counter_recovery.ex) ·
[Tests](../../../../test/examples/04_runtime/04_06_state_recovery/persistent_counter_recovery_test.exs)

## Boundary and next question

Persistence uses atomic conditional writes. A stale revision returns
`{:error, :conflict}` and preserves the newer record. The
[persistence report](../../persistence-write-results.md) also covers concurrent
writes and failed Server commits. ETS proves Agent process recovery within
one BEAM lifetime. It does not prove recovery after a node crash or provide
a distributed writer lease.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
