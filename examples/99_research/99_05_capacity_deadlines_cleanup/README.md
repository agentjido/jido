# 99_05 Shared Budget

Status: local runtime extension; not a Jido capacity API.

One admission service shares active and queued work limits across several teams.

## What this proves

- Overload and queue deadlines are checked before a worker starts.
- Worker loss releases capacity and service shutdown cleans all owned processes.

## Read the code

Read [the budget service](shared_budget.ex), then [the finite default worker](worker.ex).
The blocking worker used to inspect capacity exists only in test support.

## Run it

```sh
mix test test/examples/99_research/99_05_capacity_deadlines_cleanup --include example --seed 0
```

Expected result: accepted work stays within both limits, expired work never
starts, and shutdown stops job Agents and call Tasks.

## Gap and limits

The budget is local and temporary. It limits accepted jobs, not BEAM mailboxes,
deep Agent trees, or work on other nodes.

## Files

- [Budget service](shared_budget.ex)
- [Default worker](worker.ex)
- [Tests](../../../test/examples/99_research/99_05_capacity_deadlines_cleanup/shared_budget_test.exs)

Previous: [Handoff Reconciliation](../99_04_handoff_reconciliation/README.md) | Next: [Checkpoint Identity](../99_06_checkpoint_identity/README.md)
