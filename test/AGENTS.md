# Jido test instructions

Use `JidoTest.Case` for an isolated instance and `JidoTest.Eventually` for bounded
asynchronous assertions. Prefer barriers and process monitors to arbitrary waits.
Do not use log output, `Process.sleep/1`, or a finite `refute_receive` as a
completion signal. Use replies, process monitors, or explicit state barriers.
Capture logs only when log or redaction behavior is the contract under test.

Test complete candidate state, failure isolation, Turn order, Plugin ownership,
post-commit effects, persistence faults, remote lifecycle and resource cleanup.
Use deterministic model adapters or local HTTP/SSE for required examples.

There are four test execution categories: core, peer, benchmark, and example.
Peer tests are core contracts that start external BEAM nodes. Plain `mix test`
and `mix quality` exclude them. Run them with `mix peer --seed 0`. `mix quality`
runs fast core tests, plus format, compile, lint, and Dialyzer checks.
CI selects `mix test test/jido --include flaky --seed 0` with peer, benchmark,
and example tags excluded by the test helper.
Benchmark and example tests are secondary. Run `mix benchmarks --seed 0` or
`mix examples --seed 0` separately when needed. Give every peer test the
`:peer` tag through `JidoTest.PeerCase`. Give every benchmark test the
`:benchmark` tag and keep it in `test/bench/`.
Give every example test the `:example` tag, directly or through a
shared case template. Do not add an `:integration` tag. Keep runnable source in
`examples/`, assertions in `test/examples/`, and focused core tests in
`test/jido/`. Keep shared support in `test/support/`, core-only fixtures in
`test/jido/support/`, and example-only support in `test/examples/support/`.
Reuse fixtures; do not copy integration assertions between suites.
The DIST-03 test `one logical identity has at most one live cluster owner`
in `test/jido/agent_server/distributed_authority_test.exs` retains its approved skip.
Keep every research probe enabled. A probe that records an unsupported contract
must state the gap in its source README and keep its evidence focused on current
observable behavior. Do not add skips or exclude a group to hide a failure. A
missing or empty test selection is an error.

The runtime floor is Elixir 1.18 / OTP 27. Use Conventional Commits. Do not edit
`CHANGELOG.md`.
