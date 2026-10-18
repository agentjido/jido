# 11_03 VM Recovery

A fresh BEAM restores the same AgentServer Turn from a synced DETS file.

## What you will learn

- Supply the existing `Jido.Persistence.Adapter` byte contract.
- Own the DETS process before Jido with an application supervisor.
- Restore step 6 after SIGKILL without repeating steps 1–5.

## Read the code

Read [the supervisor](vm_recovery.ex), then [the adapter](support/dets_store.ex).
The Flow is shared with [Saved Progress](../11_02_saved_progress/saved_progress.ex).

```text
application supervisor (:rest_for_one)
  ├─ DETS owner
  └─ Jido instance
       ├─ shared Runic Runner
       └─ Agent activation supervisors
```

The adapter implements `get/2` and `compare_and_swap/4`. One GenServer serializes
conditional writes and calls `:dets.sync/1` before success. Agent records and native
graph checkpoints use the same adapter. AgentServer owns all execution decisions.

## Run it

```sh
mix test test/examples/11_durable/11_03_vm_recovery --include example --seed 0
```

Expected result: the writer saves steps 1–5, then dies while step 6 runs. The reader
starts the store and Jido, then calls `Jido.thaw/4` with persistence configured. Only steps
6–10 run in the reader. A completed Turn restores without another execution.

## Important behavior

The application explicitly restores a known Agent ID. No recovery scanner is
added. The tests use [barriers](../../../test/examples/support/durable_step_probe.ex)
and [peer controls](../../../test/examples/support/durable_peer.ex). They stop the
store and check that the DETS table closes.

## Limits

The adapter is an example for one BEAM and one local file. It is not a concurrent
BEAM writer service. The test proves BEAM loss with retained storage, not power
loss, host loss, or cluster takeover. Code must remain compatible during recovery.

## Files

- [Source](vm_recovery.ex)
- [Adapter](support/dets_store.ex)
- [Tests](../../../test/examples/11_durable/11_03_vm_recovery/vm_recovery_test.exs)
- [Adapter tests](../../../test/examples/11_durable/11_03_vm_recovery/dets_store_test.exs)

Previous: [Saved Progress](../11_02_saved_progress/README.md) | Next: [Accepted Work](../11_04_accepted_work/README.md)
