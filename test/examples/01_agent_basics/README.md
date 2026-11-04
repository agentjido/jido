# 01 Agent Basics Tests

These tests mirror the numbered source folders under
[`examples/01_agent_basics`](../../../examples/01_agent_basics/README.md). Each test module uses
the `:example` tag through the shared
[`BasicSDKCase`](../../support/basic_sdk_case.ex).

| Order | Example guide | Behavior test |
| --- | --- | --- |
| 01_01 | [Minimal Agent](../../../examples/01_agent_basics/01_01_minimal_agent/README.md) | [Test](01_01_minimal_agent/minimal_agent_test.exs) |
| 01_02 | [Typed Command Agent](../../../examples/01_agent_basics/01_02_typed_command_agent/README.md) | [Test](01_02_typed_command_agent/typed_command_agent_test.exs) |
| 01_03 | [Route Selection](../../../examples/01_agent_basics/01_03_route_selection/README.md) | [Test](01_03_route_selection/route_selection_test.exs) |
| 01_04 | [Plugin State Agent](../../../examples/01_agent_basics/01_04_plugin_state_agent/README.md) | [Test](01_04_plugin_state_agent/plugin_state_agent_test.exs) |
| 01_05 | [Directive Agent](../../../examples/01_agent_basics/01_05_directive_agent/README.md) | [Test](01_05_directive_agent/directive_agent_test.exs) |
| 01_06 | [OTP supervision](../../../examples/01_agent_basics/01_06_otp_supervision/README.md) | [Test](01_06_otp_supervision/example_test.exs) |
| 01_07 | [Data-defined Agent](../../../examples/01_agent_basics/01_07_data_defined_agent/README.md) | [Test](01_07_data_defined_agent/data_defined_agent_test.exs) |
| 01_08 | [Authoring Plugin](../../../examples/01_agent_basics/01_08_authoring_plugin/README.md) | [Test](01_08_authoring_plugin/authoring_plugin_test.exs) |

Run the section from the `jido` repository root:

```sh
mix test.examples test/examples/01_agent_basics
```

The suite uses public Jido APIs, isolated Jido instances, and explicit test-only
barriers. It does not add test controls to example Actions. It does not use
network services, credentials, arbitrary sleeps, or private runtime state.
