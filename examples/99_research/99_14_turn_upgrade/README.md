# 99_14 Turn Upgrade

Status: implemented Agent Server boundary; not an OTP release installer.

An explicit upgrade waits for the active Turn to finish before new Action code
runs on the same Agent process.

## What this proves

- An idle code load changes later behavior without replacing the Agent PID.
- `AgentServer.upgrade/3` serializes the selected load after active work.

## Read the code

Read [the Agent, reloadable Action, and Flow](turn_upgrade.ex). The blocking
Action used to create an active Turn exists only in test support.

## Run it

```sh
mix test test/examples/99_research/99_14_turn_upgrade --include example --seed 0
```

Expected result: the active Turn uses revision 1 and the next Turn uses revision
2 on the same Agent PID.

## Gap and limits

The boundary does not pin arbitrary module loads, purge code, install an OTP
release, or coordinate nodes. Promotion needs clear deployment guidance.

## Files

- [Source](turn_upgrade.ex)
- [Tests](../../../test/examples/99_research/99_14_turn_upgrade/turn_upgrade_test.exs)

Previous: [Durable Delete](../99_13_durable_delete/README.md) | Next: [State Migration](../99_15_state_migration/README.md)
