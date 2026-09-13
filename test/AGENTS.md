# Jido test instructions

Use `JidoTest.Case` for an isolated instance and `JidoTest.Eventually` for bounded
asynchronous assertions. Prefer barriers and process monitors to arbitrary waits.
Do not use log output, `Process.sleep/1`, or a finite `refute_receive` as a
completion signal. Use replies, process monitors, or explicit state barriers.
Capture logs only when log or redaction behavior is the contract under test.

Test complete candidate state, failure isolation, Turn order, Plugin ownership,
post-commit effects, persistence faults, remote lifecycle and resource cleanup.
Use deterministic model adapters or local HTTP/SSE for required examples.

There are five test execution categories: core, peer, benchmark, example, and
authoring.
Peer tests are core contracts that start external BEAM nodes. Plain `mix test`
and `mix quality` exclude them. Run them with `mix test.peer`. `mix quality`
runs fast core tests, plus format, compile, lint, and Dialyzer checks.
CI selects `mix test test/jido --include flaky --seed 0` with peer, benchmark,
example, and authoring tags excluded by the test helper.
Benchmark, example, and authoring tests are secondary. Run `mix test.bench`,
`mix test.examples`, or `mix test.authoring` separately when needed.
Run all supported test categories with
`mix test.all`. Give every peer test the
`:peer` tag through `JidoTest.PeerCase`. Give every benchmark test the
`:bench` tag and keep it in `test/bench/`.
Give every example test the `:example` tag, directly or through a
shared case template. Do not add an `:integration` tag. Keep runnable source in
`examples/`, assertions in `test/examples/`, and focused core tests in
`test/jido/`. Keep shared support in `test/support/`, core-only fixtures in
`test/jido/support/`, and example-only support in `test/examples/support/`.
Keep Agent authoring tests in `test/authoring/agents/` and Topology authoring
tests in `test/authoring/topology/`. Keep their case data, loaders, source
fixtures, and saved JSON in `test/authoring/support/agents/` and
`test/authoring/support/topology/`. Share only the compiler helper at
`test/authoring/support/compiler.exs`. Use `ExUnit.Case`
for pure authoring and planning tests; use `JidoTest.Case` only for live tests.
Keep focused core tests independent of the optional authoring corpus.
Tag authoring tests with `:authoring`. Compile source fixtures only when the suite runs;
do not add them to `elixirc_paths`. Invalid source fixtures are test inputs, not
normal compilation inputs. The authoring suite has no CI job.
Reuse fixtures; do not copy integration assertions between suites.
The DIST-03 test `one logical identity has at most one live cluster owner`
in `test/jido/agent_server/distributed_authority_test.exs` retains its approved skip.
Keep every research probe enabled. A probe that records an unsupported contract
must state the gap in its source README and keep its evidence focused on current
observable behavior. Do not add skips or exclude a group to hide a failure. A
missing or empty test selection is an error.

The runtime floor is Elixir 1.18 / OTP 27. Use Conventional Commits. Do not edit
`CHANGELOG.md`.
