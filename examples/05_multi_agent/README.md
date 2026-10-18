# Multi-agent examples

These examples cover local runtime ownership and request correlation.
The retained example numbers stay unchanged.

- [05_01 Local Lifecycle](05_01_child_lifecycle/README.md)
- [05_02 Correlated Requests](05_02_correlated_requests/README.md)
- [05_06 Orphan Adoption](05_06_orphan_adoption/README.md)

The API update for these examples is still in progress. Nested definition
ownership is covered by [07_02 Nested Agents](../07_topology/07_02_hierarchy/README.md).
Remote placement and node-loss behavior remain [research](../99_research/README.md).

```sh
mix test test/examples/05_multi_agent --include example --seed 0
```

The [Worker](support/worker.ex) supports local lifecycle and correlation.
These examples do not provide cluster ownership or automatic remote failover.
