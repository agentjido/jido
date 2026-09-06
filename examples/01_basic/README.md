# 01 Basic examples

Each fixture uses the V3 command contract. Its tests check real framework behavior.
Run the full acceptance command from the repository root.

| Fixture | Source | Tests | Contract |
| --- | --- | --- | --- |
| 01_01_minimal_agent | [Source](01_01_minimal_agent/minimal_agent.ex) | [Tests](../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs) | Direct/live agreement and instance isolation. |
| 01_02_typed_command_agent | [Source](01_02_typed_command_agent/typed_command_agent.ex) | [Tests](../../test/examples/01_basic/01_02_typed_command_agent/typed_command_agent_test.exs) | Construction, route selection, input validation, and complete candidate validation. |
| 01_03_plugin_state_agent | [Source](01_03_plugin_state_agent/plugin_state_agent.ex) | [Tests](../../test/examples/01_basic/01_03_plugin_state_agent/plugin_state_agent_test.exs) | Plugin state ownership and atomic domain/Plugin commit. |
| 01_04_directive_agent | [Source](01_04_directive_agent/directive_agent.ex) | [Tests](../../test/examples/01_basic/01_04_directive_agent/directive_agent_test.exs) | Whole-batch validation and ordered post-commit dispatch. |
| 01_05_controlled_turn_agent | [Source](01_05_controlled_turn_agent/controlled_turn_agent.ex) | [Tests](../../test/examples/01_basic/01_05_controlled_turn_agent/controlled_turn_agent_test.exs) | Turn serialization, cancellation, queued work, and caller timeout. |

See [all examples](../README.md) and [migration](../../guides/migration.md).
