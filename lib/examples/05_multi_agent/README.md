# Multi-agent feature examples

This sequence has six source fixtures and 38 passing tests. The first four use
18 opt-in example tests. The two promoted distributed Agent examples use 20
two-node core acceptance tests.

| Order | Added feature | Tests |
| --- | --- | ---: |
| [05_01_child_lifecycle](05_01_child_lifecycle/child_lifecycle.ex) | A parent starts, tracks, restarts, and stops owned children. | 3 example |
| [05_02_correlated_requests](05_02_correlated_requests/correlated_requests.ex) | Parent and child work use separate Turns and correlated replies. | 6 example |
| [05_03_bounded_workers](05_03_bounded_workers/bounded_workers.ex) | Fixed worker slots bound live child count and preserve result order. | 5 example |
| [05_04_agent_hierarchy](05_04_agent_hierarchy/agent_hierarchy.ex) | Direct ownership isolates branch loss and cleans the full tree. | 4 example |
| [05_05_remote_child](05_05_remote_child/remote_child.ex) | A parent places and owns a child on a selected Erlang node. | 16 core |
| [05_06_remote_lifecycle](05_06_remote_lifecycle/remote_lifecycle.ex) | Node loss, disconnect, parent loss, and replacement have explicit outcomes. | 4 core |

Run the opt-in example tests:

```shell
mix test --include integration test/examples/05_multi_agent --seed 0
```

Run the remote child demonstration:

```shell
mix run lib/examples/05_multi_agent/05_05_remote_child/demo.exs
```

See the [Multi-agent profiles](../../../docs/examples/catalog.md#multi-agent)
and the [distributed authority queue item](../99_research/99_02_distributed_authority/README.md).
