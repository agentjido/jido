# Multi-agent feature examples

Multi-agent has six source fixtures and 38 passing tests. The first four use 18
opt-in tests in this directory. The two promoted distributed Agent examples
keep 20 acceptance tests under `test/jido/agent`.

| Order | Test location | Tests |
| --- | --- | ---: |
| `05_01` through `05_04` | Numbered test files in this directory | 18 |
| [05_05_remote_child](05_05_remote_child/README.md) | `test/jido/agent/child_placement_test.exs` and `distributed_child_test.exs` | 16 |
| [05_06_remote_lifecycle](05_06_remote_lifecycle/README.md) | `test/jido/agent/remote_lifecycle_test.exs` | 4 |

```shell
mix test --include integration test/examples/05_multi_agent --seed 0
```

[Source guide](../../../lib/examples/05_multi_agent/README.md) ·
[Catalog](../../../docs/examples/catalog.md#multi-agent)
