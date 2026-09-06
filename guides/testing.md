# Test the V3 candidate

Use an isolated named Jido instance for each live test. Check direct candidate
results separately from live commits and later directive outcomes. Use barriers
and process monitors for ordering, failure, replacement, and cleanup.

The complete suite currently runs with:

```sh
mix test --include example --include flaky --seed 0
```

Default `mix test` excludes `:example`, `:flaky`, and the approved `:skip` test.
All example tests, including the former integration scenarios, use `:example`.
`mix examples --seed 0` selects that complete example suite. Run the complete
command above to include the supporting core and remote acceptance tests.

The [example catalog](https://github.com/agentjido/jido/tree/v3-spike/examples/README.md) has 52 fixtures and ten
additional application scenarios. Source files live in `examples/`; tests live
in `test/examples/`. Production builds and the Hex package exclude both trees.
Local development and test builds compile the source examples so demos and
shared core regression fixtures remain available.
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
mix test --cover test/jido test/jido_test test/examples/08_applications --include example --include flaky --seed 0
```

CI uses the same paths without `--cover`. The application examples remain in
CI through that explicit selection. The other examples run separately.
Example source lines do not count toward the core coverage goal; all selected
tests can contribute coverage of the core modules they call.

To run the complete suite and measure core coverage in one run, use:

```sh
mix test --include example --include flaky --seed 0 --cover
```

The Mix summary threshold and ExCoveralls minimum are both 90%. Keep the
coverage scope and enabled acceptance checks intact when adding tests.
Coverage runs also collect counters from the isolated BEAM test nodes before
they stop. The report includes the same measured modules on each node.
