# 99_03 Input Resource Lifecycle

Status: implemented contract; not yet promoted to the stable Plugin examples.

A Plugin runtime reconstructs one disposable input resource from committed
Plugin state and its state version.

## What this proves

- Initial and replacement runtimes receive the correct committed Plugin state.
- A resource closes on replacement, stale input is rejected, and new input continues.

## Read the code

Read [the Agent](runtime_reconstruction.ex), [the Plugin](plugin.ex), then
[the runtime](runtime.ex).

## Run it

```sh
mix test test/examples/99_research/99_03_input_resource_lifecycle --include example --seed 0
```

Expected result: feed A changes to B, the Plugin runtime restarts on B, and all
old resources stop.

## Gap and limits

Promotion should merge this resource-lifecycle detail with the stable
subscription example. The resource is local and does not model provider replay
or duplicate event IDs.

## Files

- [Agent](runtime_reconstruction.ex)
- [Plugin](plugin.ex)
- [Runtime](runtime.ex)
- [Tests](../../../test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs)

Previous: [Distributed Authority](../99_02_distributed_authority/README.md) | Next: [Handoff Reconciliation](../99_04_handoff_reconciliation/README.md)
