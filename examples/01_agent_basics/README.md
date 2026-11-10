# 01 Agent Basics

Start with 01_01, 01_02, and 01_03. Then add Plugin state, Directives, and
supervision. Keep the data and extension lessons for the authoring path.
Numbers are stable IDs; the table gives the reading order.

| ID | Example | Main capability |
| --- | --- | --- |
| 01_01 | [Minimal Agent](01_01_minimal_agent/README.md) | Agent state, inline Actions, command helpers, and direct or live execution |
| 01_02 | [Typed Command Agent](01_02_typed_command_agent/README.md) | Typed Action input, route defaults, and complete candidate validation |
| 01_03 | [Route Selection](01_03_route_selection/README.md) | Exact routes, wildcard fallback, precedence, and direct or live parity |
| 01_04 | [Plugin State Agent](01_04_plugin_state_agent/README.md) | Plugin-owned state and atomic commit |
| 01_05 | [Directive Agent](01_05_directive_agent/README.md) | Whole-batch validation and ordered post-commit effects |
| 01_06 | [OTP supervision](01_06_otp_supervision/README.md) | Activation supervisor tree, worker restart, local checkpoints, and shutdown |
| 01_07 | [Data-defined Agent](01_07_data_defined_agent/README.md) | Neutral definitions, trusted Catalog and Codec, and Plugin documents |
| 01_08 | [Authoring Plugin](01_08_authoring_plugin/README.md) | Static Plugin declarations stored as validated, versioned contributions |

Run the section from the `jido` repository root:

```sh
mix test.examples test/examples/01_agent_basics
```

The examples use deterministic local processes. They need no credentials or
network access. Durable recovery, external services, and multi-agent systems
belong to later sections.

See [all examples](../README.md) and the [matching test guide](../../test/examples/01_agent_basics/README.md).
