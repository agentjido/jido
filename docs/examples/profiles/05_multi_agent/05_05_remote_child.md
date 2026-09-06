# Remote Child

Feature ID: `05_05_remote_child`. Status: implemented within the tested scope.

## Added feature

A parent places and owns a child Agent on a selected Erlang node. Signals,
restart, stop, parent loss, delayed creation, and request identity use the same
Agent contract across nodes.

## Evidence

Sixteen core tests use two real Erlang nodes.

```shell
mix test test/jido/agent/child_placement_test.exs test/jido/agent/distributed_child_test.exs --seed 0
mix run examples/05_multi_agent/05_05_remote_child/demo.exs
```

[Source](../../../../examples/05_multi_agent/05_05_remote_child/remote_child.ex) ·
[Core tests](../../../../test/jido/agent/distributed_child_test.exs) ·
[Results](../../dist-01-results.md)
