# Test the V3 candidate

Use an isolated named Jido instance for each live test. Check direct candidate
results separately from live commits and later directive outcomes. Use barriers
and process monitors for ordering, failure, replacement, and cleanup.
Do not use `Process.sleep/1` or a finite `refute_receive` as a
completion signal. Use replies, process monitors, or explicit state barriers.
Core tests capture logs only when log or redaction behavior is the contract.
System and service tests can watch scoped logs for readiness and failure
evidence. Confirm service readiness with a real protocol or state check.
These suites use event waits, not sleep timers or repeated polling.

The default quality check runs core tests, plus format, compile, lint, and
Dialyzer checks:

```sh
mix quality
```

There are six normal categories and separate opt-in service profiles:

| Category | Command | Default quality check |
| --- | --- | --- |
| Core | `mix test test/jido --include flaky --seed 0` | Included |
| Peer core | `mix test.peer` | Not included |
| Benchmark | `mix test.bench` | Not included |
| Example, including research | `mix test.examples` | Not included |
| Agent and Topology authoring | `mix test.authoring` | Not included |
| Local runtime faults and recovery | `mix test.system` | Not included |
| External storage services (opt-in) | `mix test.services` | Not included |
| Bedrock/MinIO snapshots (opt-in) | `mix test.services.minio` | Not included |

CI and the test step in `mix quality` use
`mix test test/jido --include flaky --seed 0`. They run fast core tests with a
fixed seed, including the tagged flaky tests but excluding peer tests.

Default `mix test` excludes `:bench`, `:example`, `:authoring`, `:system`, `:service`, `:flaky`, `:peer`, and
approved `:skip` tests. Tests that use `JidoTest.PeerCase` get the `:peer` tag
and start actual BEAM nodes. Run peer and example tests separately when needed:

```sh
mix test.peer
mix test.examples
```

Benchmark tests in `test/bench/` use the `:bench` tag. All example tests,
including the former integration scenarios, use `:example`.

The Agent and Topology authoring corpus in `test/authoring/` uses `:authoring`.
Run it with `mix test.authoring`. Both sets check source compilation, definition
parity, saved JSON, and instantiation. Agent cases compare direct and live
execution. Topology cases check pure plans without starting a controller.
Source fixtures load only when the suite runs. There is no authoring CI job. See the
[corpus guide](../test/authoring/README.md) for cases and extension rules.

The runtime system suite in `test/system/` checks state, effect, resource, and
observability invariants under controlled faults. `mix test.system` runs real
ETS, File, and SQLite/Ecto scenarios in `test/system/runtime/`.
`mix test.services` runs Redis, PostgreSQL and real Bedrock scenarios in
the top level of `test/system/services/`, including cluster restart and strict
multi-node probes. `mix test.services.minio` selects the nested MinIO profile
and requires an explicit test endpoint and credentials.
Service tests are not part of `mix test.all` and never start from that command.
Base Bedrock tests use local file object storage. The MinIO profile checks real
S3 snapshot upload and cold materializer recovery. The suites keep unresolved probes
enabled, so a full run can fail on a documented unsupported contract.
See [system tests](../test/system/README.md) for prerequisites and exact limits.
Use `elixir test/system/burn_in.exs --runs 5 --rounds 100 --seed 93` for opt-in
fresh-BEAM model repetition. It has no CI job and does not replace the full suite.

All research example tests pass without skips. They include the explicit
quiescent upgrade boundary, validated definition migration, and additive
Topology update. See the
[research results](../test/examples/99_research/README.md).

The [example catalog](https://github.com/agentjido/jido/blob/release/v3/examples/README.md) has 62 main fixtures and
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

CI uses the same paths without `--cover`. Benchmark, example, authoring, system,
and service tests run separately. There is no new CI job for these profiles.
Example source lines do not count toward the core coverage goal; all selected
tests can contribute coverage of the core modules they call.

Run all six normal categories, without external storage services, with:

```sh
mix test.all
```

As an optional secondary check, run all six categories with core coverage:

```sh
mix test.all --cover
```

The Mix summary threshold and ExCoveralls minimum are both 90%. Keep the
coverage scope intact when adding tests. Do not add skips to meet the threshold.
Coverage runs that include `:peer` also collect counters from the isolated BEAM
test nodes before they stop. The report includes the same measured modules on
each node.
