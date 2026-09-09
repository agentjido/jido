# UP-01: Turn upgrade

All three tests pass.

Two Flow steps call one Action module. A barrier pauses one active Turn between
the steps. `Jido.AgentServer.upgrade/3` waits for the Turn to finish before it
loads the new code. The active Turn stays on revision 1. The next Turn on the
same Agent PID uses revision 2.

## Implemented core feature

Core provides an explicit idle upgrade boundary. A revision label does not
isolate arbitrary module loads, and this example does not claim that it does.

## Run

```sh
mix test test/examples/99_research/99_14_turn_upgrade --include example --seed 0 --trace
```

All assertions are enabled. Current startup and ordinary Turn APIs retain their
existing contracts.

## Scope

Only one isolated Action module is reloaded. Tests run serially. The loader does not force a code purge. This is not an OTP release installer.

[Source](turn_upgrade.ex) · [Tests](../../../test/examples/99_research/99_14_turn_upgrade/turn_upgrade_test.exs)
