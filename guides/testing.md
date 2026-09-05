# Test the V3 candidate

Use an isolated named Jido instance for each live test. Check direct candidate
results separately from live commits and later directive outcomes. Use barriers
and process monitors for ordering, failure, replacement, and cleanup.

The complete suite currently runs with:

```sh
mix test --include example --include integration --include flaky --seed 0
```

Default `mix test` excludes examples and flaky-tagged tests. `mix examples`
alone does not include every supporting core test or application scenario.
The complete migration gate must reject missing or empty selections, duplicate
identities, failures, and every exclusion except the exact DIST-03 record.

The checked manifest has 52 catalog fixtures and ten application scenarios.
Deterministic model adapters and local HTTP/SSE tests require no provider key.
Remote tests start actual BEAM peers. Keep their clock separation and shutdown
checks. A local File adapter test does not prove multi-process storage safety.

Each recorded command stores its source hash, runtime, seed, individual test
results, and log under `docs/migration/evidence/core`. Failed records remain as
investigation evidence. The final gate also requires seeds 0–9, a 30-minute
recovery workload, independent scale checks, and local beta QA.

See [validation requirements](../docs/migration/05-validation.md) and
[the execution record](../docs/migration/10-execution-record.md).
