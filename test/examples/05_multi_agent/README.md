# Multi-agent feature examples

Multi-agent has six source fixtures and 20 opt-in tests in this directory. The
two promoted distributed Agent examples also keep deeper acceptance tests
under `test/jido/agent_server` and `test/jido/observe`.

| Order | Test location | Tests |
| --- | --- | ---: |
| `05_01` through `05_04` | Numbered test files in this directory | 18 |
| [05_05_remote_child](05_05_remote_child/README.md) | Numbered test file plus distributed core suites | 1 example |
| [05_06_remote_lifecycle](05_06_remote_lifecycle/README.md) | Numbered test file plus remote-lifecycle core suite | 1 example |

```shell
mix test --include example test/examples/05_multi_agent --seed 0
```

[Source guide](../../../examples/05_multi_agent/README.md)
