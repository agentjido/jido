# Basic example tests

These tests mirror the numbered source folders under
[`examples/01_basic`](../../../examples/01_basic/README.md). Each test module uses
the `:example` tag through the shared
[`BasicSDKCase`](../support/basic_sdk_case.ex).

| Order | Example guide | Behavior test |
| --- | --- | --- |
| 01_01 | [Minimal Agent](../../../examples/01_basic/01_01_minimal_agent/README.md) | [Test](01_01_minimal_agent/minimal_agent_test.exs) |
| 01_02 | [Typed Command Agent](../../../examples/01_basic/01_02_typed_command_agent/README.md) | [Test](01_02_typed_command_agent/typed_command_agent_test.exs) |
| 01_03 | [Plugin State Agent](../../../examples/01_basic/01_03_plugin_state_agent/README.md) | [Test](01_03_plugin_state_agent/plugin_state_agent_test.exs) |
| 01_04 | [Directive Agent](../../../examples/01_basic/01_04_directive_agent/README.md) | [Test](01_04_directive_agent/directive_agent_test.exs) |
| 01_05 | [Controlled Turn Agent](../../../examples/01_basic/01_05_controlled_turn_agent/README.md) | [Test](01_05_controlled_turn_agent/controlled_turn_agent_test.exs) |

Run the section from the `jido` repository root:

```sh
mix test test/examples/01_basic --include example --seed 0
```

The suite uses public Jido APIs, isolated Jido instances, explicit barriers, and
process monitors. It does not use network services, credentials, arbitrary
sleeps, or private execution messages.
