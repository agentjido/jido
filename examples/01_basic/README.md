# Basic examples

Read these examples in order. They start with a small Agent and then add one
runtime boundary at a time.

| Order | Example | Main capability |
| --- | --- | --- |
| 01_01 | [Minimal Agent](01_01_minimal_agent/README.md) | Agent state, inline Actions, command helpers, and direct or live execution |
| 01_02 | [Typed Command Agent](01_02_typed_command_agent/README.md) | Typed Action input, route defaults, and complete candidate validation |
| 01_03 | [Plugin State Agent](01_03_plugin_state_agent/README.md) | Plugin-owned state and atomic commit |
| 01_04 | [Directive Agent](01_04_directive_agent/README.md) | Whole-batch validation and ordered post-commit effects |
| 01_05 | [Controlled Turn Agent](01_05_controlled_turn_agent/README.md) | Turn serialization, cancellation, worker cleanup, and caller timeout |

Run the section from the `jido` repository root:

```sh
mix test test/examples/01_basic --include example --seed 0
```

The examples use deterministic local processes. They need no credentials or
network access. Durable recovery, external services, and multi-agent systems
belong to later sections.

See [all examples](../README.md), [the matching test guide](../../test/examples/01_basic/README.md), and [migration guidance](../../guides/migration.md).
