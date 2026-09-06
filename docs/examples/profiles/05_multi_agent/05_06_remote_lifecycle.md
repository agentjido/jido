# Remote Lifecycle

Feature ID: `05_06_remote_lifecycle`. Status: implemented within the tested scope.

## Added feature

A parent distinguishes a confirmed remote process exit from an unreachable
node, stops remote work after parent loss, and requires explicit replacement
after reconnect.

## Evidence

Four core tests use two live Erlang nodes and a real distribution disconnect.

```shell
mix test test/jido/agent/remote_lifecycle_test.exs --seed 0
```

[Source](../../../../examples/05_multi_agent/05_06_remote_lifecycle/remote_lifecycle.ex) ·
[Core tests](../../../../test/jido/agent/remote_lifecycle_test.exs) ·
[Results](../../dist-02-results.md)
