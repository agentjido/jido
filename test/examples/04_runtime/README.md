# Runtime feature examples

Runtime has 13 source fixtures and 34 opt-in tests in this directory. The five
promoted capability examples also keep deeper acceptance tests under
`test/jido`, beside the core contracts that they prove.

| Order | Test location | Tests |
| --- | --- | ---: |
| `04_01` through `04_08` | Numbered test files in this directory | 29 |
| [04_09_agent_observation](04_09_agent_observation/README.md) | Numbered test file plus observation core suite | 1 example |
| [04_10_causal_trace](04_10_causal_trace/README.md) | Numbered test file plus causal-trace core suite | 1 example |
| [04_11_recoverable_delivery](04_11_recoverable_delivery/README.md) | Numbered test file plus recovery core suite | 1 example |
| [04_12_pending_job_recovery](04_12_pending_job_recovery/README.md) | Numbered test file plus job-recovery core suite | 1 example |
| [04_13_durable_scheduling](04_13_durable_scheduling/README.md) | Numbered test file plus Scheduler core suite | 1 example |

```shell
mix test --include example test/examples/04_runtime --seed 0
```

[Source guide](../../../examples/04_runtime/README.md)
