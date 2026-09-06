# Runtime feature examples

Runtime has 13 source fixtures and 93 passing tests. The first eight use 29
opt-in tests in this directory. The five promoted capability examples keep 64
acceptance tests under `test/jido`, beside the core contracts that they prove.

| Order | Test location | Tests |
| --- | --- | ---: |
| `04_01` through `04_08` | Numbered test files in this directory | 29 |
| [04_09_agent_observation](04_09_agent_observation/README.md) | `test/jido/observe/agent_lifecycle_test.exs` | 9 |
| [04_10_causal_trace](04_10_causal_trace/README.md) | `test/jido/observe/*causal_trace_test.exs` | 12 |
| [04_11_recoverable_delivery](04_11_recoverable_delivery/README.md) | `test/jido/agent/effect_recovery_test.exs` | 11 |
| [04_12_pending_job_recovery](04_12_pending_job_recovery/README.md) | `test/jido/agent/pending_job*_test.exs` | 7 |
| [04_13_durable_scheduling](04_13_durable_scheduling/README.md) | Scheduler and scheduled occurrence core tests | 25 |

```shell
mix test --include example test/examples/04_runtime --seed 0
```

[Source guide](../../../examples/04_runtime/README.md) ·
[Catalog](../../../docs/examples/catalog.md#runtime)
