# Test the V3 candidate

Use an isolated named Jido instance for each live test. Check direct candidate
results separately from live commits and later directive outcomes. Use barriers
and process monitors for ordering, failure, replacement, and cleanup.
Do not use log output, `Process.sleep/1`, or a finite `refute_receive` as a
completion signal. Use replies, process monitors, or explicit state barriers.
Capture logs only when log or redaction behavior is the contract under test.

The default quality check runs core tests, plus format, compile, lint, and
Dialyzer checks:

```sh
mix quality
```

There are three test categories:

| Category | Command | Default quality check |
| --- | --- | --- |
| Core | `mix test test/jido --include flaky --seed 0` | Included |
| Benchmark | `mix benchmarks --seed 0` | Not included |
| Example, including research | `mix examples --seed 0` | Not included |

CI and the test step in `mix quality` use
`mix test test/jido --include flaky --seed 0`. They run core tests
with a fixed seed, including the tagged flaky core tests.

Default `mix test` excludes `:benchmark`, `:example`, `:flaky`, and approved
`:skip` tests. Benchmark tests in `test/bench/` use the `:benchmark` tag.
All example tests, including the former integration scenarios, use `:example`.
Run examples separately when needed:

```sh
mix examples --seed 0
```

All research example tests pass without skips. They include the explicit
quiescent upgrade boundary, validated definition migration, and additive local
Topology update. See the
[research results](../test/examples/99_research/README.md).

The [example catalog](https://github.com/agentjido/jido/tree/v3-spike/examples/README.md) has 62 main fixtures and
16 research probes. Source files live in `examples/`; tests live in
`test/examples/`. Production builds and the Hex package exclude both trees.
Local development and test builds compile the source examples so demos and
shared core regression fixtures remain available.
Deterministic model adapters and local HTTP/SSE tests require no provider key.
Remote tests start actual BEAM peers. Keep their caller-clock and shutdown
checks. A local File adapter test does not prove multi-process storage safety.

The core suite also retains the approved skip for the DIST-03 test
`one logical identity has at most one live cluster owner` in
`test/jido/agent_server/distributed_authority_test.exs`. Cluster-exclusive ownership
remains unsupported. Preserve the test assertion and its stated reason.

## Core coverage

The 90% coverage requirement applies to core code in `lib/jido.ex` and `lib/jido/`.
Use 93% as a preferred development buffer, not as the release threshold.
`coveralls.json` excludes example code, test fixtures, and benchmark helpers.
Run core-test coverage with:

```sh
mix test --cover test/jido --include flaky --seed 0
```

CI uses the same paths without `--cover`. Benchmark and example tests run separately.
Example source lines do not count toward the core coverage goal; all selected
tests can contribute coverage of the core modules they call.

As an optional secondary check, run all three categories with core coverage:

```sh
mix test --include benchmark --include example --include flaky --seed 0 --cover
```

The Mix summary threshold and ExCoveralls minimum are both 90%. Keep the
coverage scope intact when adding tests. Do not add skips to meet the threshold.
Coverage runs also collect counters from the isolated BEAM test nodes before
they stop. The report includes the same measured modules on each node.
