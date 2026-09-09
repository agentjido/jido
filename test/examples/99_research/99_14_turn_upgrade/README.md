# UP-01: Turn upgrade

All three tests pass with no skip.

Two Flow steps call one Action module. A barrier pauses one active Turn between
the steps. The explicit Agent Server upgrade operation waits for idle, loads
the new code, and lets the next Turn use it on the same Agent PID.

## Implemented core feature

The upgrade boundary serializes an operator-selected code installation with
Turns. It does not pin arbitrary module loads.

## Run

```sh
mix test test/examples/99_research/99_14_turn_upgrade --include example --seed 0 --trace
```

This is a secondary check. All assertions are enabled. Current startup and
ordinary Turn APIs retain their existing contracts.

## Scope

Only one isolated Action module is reloaded. Tests run serially. The loader does not force a code purge. This is not an OTP release installer.

[Source](../../../../examples/99_research/99_14_turn_upgrade/turn_upgrade.ex) · [Tests](turn_upgrade_test.exs)
