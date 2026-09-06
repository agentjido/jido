# Test the V3 candidate

Use an isolated named Jido instance for each live test. Check direct candidate
results separately from live commits and later directive outcomes. Use barriers
and process monitors for ordering, failure, replacement, and cleanup.

The complete suite currently runs with:

```sh
mix test --include example --include integration --include flaky --seed 0
```

Default `mix test` excludes examples, integration tests, and flaky-tagged tests.
`mix examples` alone does not include every supporting core test or application
scenario. Run the complete command above before release.

The [example catalog](../lib/examples/README.md) has 52 fixtures and ten
additional application scenarios.
Deterministic model adapters and local HTTP/SSE tests require no provider key.
Remote tests start actual BEAM peers. Keep their clock separation and shutdown
checks. A local File adapter test does not prove multi-process storage safety.

The only approved exclusion is the DIST-03 test
`one logical identity has at most one live cluster owner` in
`test/jido/agent/distributed_authority_test.exs`. Cluster-exclusive ownership
remains unsupported. Preserve the test assertion and its stated reason.

## Core coverage

The 90% coverage requirement applies to core code in `lib/jido.ex` and `lib/jido/`.
Keep total core coverage above 93% to allow for new work.
`coveralls.json` excludes example code, test fixtures, and benchmark helpers.
Run core coverage with:

```sh
mix test --cover test/jido test/jido_test test/integration --include integration --include flaky --seed 0
```

Run example tests separately for behavior checks. Their coverage is not part of
the core coverage goal.

To run the complete suite and measure core coverage in one run, use:

```sh
mix test --include example --include integration --include flaky --seed 0 --cover
```

The Mix summary threshold and ExCoveralls minimum are both 90%. Keep the
coverage scope and enabled acceptance checks intact when adding tests.
Coverage runs also collect counters from the isolated BEAM test nodes before
they stop. The report includes the same measured modules on each node.
