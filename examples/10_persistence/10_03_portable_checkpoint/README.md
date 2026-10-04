# 10_03 Portable Checkpoint

Persistence accepts portable domain data and rejects process-local BEAM values.

## What you will learn

- How default checkpoints validate the complete stored value.
- Why PIDs, ports, references, functions, improper lists, and bitstrings cannot be durable state.

## Read the code

Read [the payload Agent](checkpoint_portability_probe.ex), then read its behavior test.

## Run it

`mix test test/examples/10_persistence/10_03_portable_checkpoint --include example --seed 0`

Expected result: portable nested data saves and loads. A stored PID is rejected with its value path.

## Important behavior

Schema acceptance does not prove storage portability. Jido checks portability after custom conversion and before it accepts a record.

## Limits

This example does not test a VM restart. The core suite tests all prohibited term classes and cross-BEAM atom loading.

## Files

- [Source](checkpoint_portability_probe.ex)
- [Tests](../../../test/examples/10_persistence/10_03_portable_checkpoint/checkpoint_portability_test.exs)

Previous: [Hibernate And Thaw](../10_02_hibernate_and_thaw/README.md) | Next: [Plugin State Conversion](../10_04_plugin_state_conversion/README.md)
