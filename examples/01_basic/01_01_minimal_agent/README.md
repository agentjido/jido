# Minimal Agent

This example solves a small state problem: keep a counter and change it with a
Signal. It teaches the Agent DSL, an inline Action, route defaults, generated
command helpers, direct execution, and live Agent Server execution.

## Read the files

1. Read [the Agent](minimal_agent.ex).
2. Read [the behavior tests](../../../test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs).
3. Read [the shared test case](../../../test/examples/support/basic_sdk_case.ex) if you want to see how the isolated Jido instance starts.

## Run the example

Run this command from the `jido` repository root:

```sh
mix test test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs --include example --seed 0
```

The tests show that direct and live commands use the same defaults and Signal
overrides. They also show that two Agent instances keep separate state.

Invalid Action input does not change committed state. A later valid command can
still commit. The isolated Jido instance stops all Agent Servers after each test.

This example does not teach Plugins, Directives, persistence, or concurrent
Turns.

[Back to Basic](../README.md) · [Next: Typed Command Agent](../01_02_typed_command_agent/README.md)
