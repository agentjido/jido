# Recoverable Delivery

Feature ID: `04_11_recoverable_delivery`. Status: implemented within the tested scope.

## Added feature

Business state and delivery intent commit together. A supervised Plugin resumes
pending output after Agent or Plugin loss and confirms completion in a new Turn.

## Evidence

Eleven core tests cover stable effect identity, duplicate policy, both sides of
delivery, recovery, unavailable output, and failed persistence writes.

```shell
mix test test/jido/agent/effect_recovery_test.exs --seed 0
mix run examples/04_runtime/04_11_recoverable_delivery/demo.exs
```

[Source](../../../../examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex) ·
[Core tests](../../../../test/jido/agent/effect_recovery_test.exs) ·
[Results](../../rec-01-results.md)
