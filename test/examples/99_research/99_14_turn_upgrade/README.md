# UP-01: Turn upgrade

The baseline has two passing tests and one failure. As of 2026-09-07,
the failing test is temporarily skipped, with its assertion retained.
See the [research test policy](../README.md).

Two Flow steps call one Action module. A barrier permits a controlled code load between the steps. Idle replacement changes executed behavior on the same Agent PID. The active Turn mixes revisions and returns 11 instead of 2.

## Required core feature

Core needs an explicit revision boundary for the complete Turn. A revision label alone cannot isolate arbitrary module loads.

## Run

```sh
mix test test/examples/99_research/99_14_turn_upgrade --include example --seed 0 --trace
```

This is a secondary check. The skipped assertion states desired upgrade
behavior. When the explicit upgrade API exists, connect this example to it
and remove the skip. Current startup and ordinary Turn APIs retain their
existing contracts.

## Scope

Only one isolated Action module is reloaded. Tests run serially. The loader does not force a code purge. This is not an OTP release installer.

[Source](../../../../examples/99_research/99_14_turn_upgrade/turn_upgrade.ex) · [Tests](turn_upgrade_test.exs)
