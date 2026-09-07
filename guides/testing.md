# Test the V3 candidate

Use an isolated named Jido instance for each live test. Check direct candidate
results separately from live commits and later directive outcomes. Use barriers
and process monitors for ordering, failure, replacement, and cleanup.

The default release check runs the core suite:

```sh
mix test test/jido test/jido_test --include flaky --seed 0
```

CI uses this command. Example acceptance tests are secondary and do not run in
the default release check.

Default `mix test` excludes `:example`, `:flaky`, and approved `:skip` tests.
All example tests, including the former integration scenarios, use `:example`.
Run examples separately when needed:

```sh
mix examples --seed 0
```

The 11 known failing research tests are temporarily skipped. They describe
proposed features that Core does not implement. Each skip names the missing
feature; the original assertion remains. Remove the skip when the feature is
implemented. See the [research results](../test/examples/99_research/README.md).
A passing core suite does not prove these proposed contracts.

The [example catalog](https://github.com/agentjido/jido/tree/v3-spike/examples/README.md) has 52 fixtures and ten
additional application scenarios. Source files live in `examples/`; tests live
in `test/examples/`. Production builds and the Hex package exclude both trees.
Local development and test builds compile the source examples so demos and
shared core regression fixtures remain available.
Deterministic model adapters and local HTTP/SSE tests require no provider key.
Remote tests start actual BEAM peers. Keep their clock separation and shutdown
checks. A local File adapter test does not prove multi-process storage safety.

The core suite also retains the approved skip for the DIST-03 test
`one logical identity has at most one live cluster owner` in
`test/jido/agent/distributed_authority_test.exs`. Cluster-exclusive ownership
remains unsupported. Preserve the test assertion and its stated reason.

## Core coverage

The 90% coverage requirement applies to core code in `lib/jido.ex` and `lib/jido/`.
Keep total core coverage above 93% to allow for new work.
`coveralls.json` excludes example code, test fixtures, and benchmark helpers.
Run core coverage with:

```sh
mix test --cover test/jido test/jido_test --include flaky --seed 0
```

CI uses the same paths without `--cover`. All examples run separately.
Example source lines do not count toward the core coverage goal; all selected
tests can contribute coverage of the core modules they call.

As an optional secondary check, run core and examples with core coverage:

```sh
mix test --include example --include flaky --seed 0 --cover
```

The Mix summary threshold and ExCoveralls minimum are both 90%. Keep the
coverage scope intact when adding tests. Do not add skips to meet the threshold.
Coverage runs also collect counters from the isolated BEAM test nodes before
they stop. The report includes the same measured modules on each node.
