# 07_04 Keyed Accounts

A Topology creates stable Agent identities from explicit account keys in input
records.

## What you will learn

- How `members` and `key_by` expand a keyed group.
- How member input sets each Agent's initial state.

## Read the code

Read [the account Topology](accounts.ex), then the shared [Cell Agent](../support/cell.ex).

## Run it

```sh
mix test test/examples/07_topology/07_04_keyed_accounts --include example --seed 0
```

Expected result: the account key `acme/east` resolves to an Agent whose label is
`Acme`. After a failure, the same key resolves to a new process with the same
ID, committed state, and revision. The other account keeps its PID. Controller
shutdown removes both Agents.

## Important behavior

Keys normalize to stable strings. Slashes are escaped in Agent IDs; lookups use
the original account key. Duplicate keys fail planning before startup.

## Limits

Input is an in-memory record list. This example does not include a database adapter.

## Files

- [Source](accounts.ex)
- [Tests](../../../test/examples/07_topology/07_04_keyed_accounts/keyed_accounts_test.exs)
- [Cell Agent](../support/cell.ex)

Previous: [Bus Swarm](../07_03_bus_swarm/README.md) | Next: [Composed System](../07_05_composed_system/README.md)
