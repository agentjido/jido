# Application example tests

These tests cover the ten [application examples](../../../examples/08_applications/README.md).
The source compiles with the other examples. Each test file uses `:example` and
runs once; no fixture file uses the `_test.exs` suffix.

Source and test folders share the same numbered ID:

| ID | Test file |
| --- | --- |
| 08_01_audit | [Audit](08_01_audit/audit_test.exs) |
| 08_02_subscription | [Subscription](08_02_subscription/subscription_test.exs) |
| 08_03_inbox | [Inbox](08_03_inbox/inbox_test.exs) |
| 08_04_identity | [Identity](08_04_identity/identity_test.exs) |
| 08_05_secure_signal | [Secure Signal](08_05_secure_signal/secure_signal_test.exs) |
| 08_06_coordinator | [Coordinator](08_06_coordinator/coordinator_test.exs) |
| 08_07_react | [ReAct](08_07_react/react_test.exs) |
| 08_08_purpose_loop | [Purpose Loop](08_08_purpose_loop/purpose_loop_test.exs) |
| 08_09_fixed_group | [Fixed Group](08_09_fixed_group/fixed_group_test.exs) |
| 08_10_elastic_group | [Elastic Group](08_10_elastic_group/elastic_group_test.exs) |

```sh
mix test test/examples/08_applications --include example --seed 0
mix test test/examples/08_applications/08_01_audit --include example --seed 0
```

The default test command skips these tests. `mix examples` includes them.
CI selects this directory explicitly to preserve its existing acceptance checks.
