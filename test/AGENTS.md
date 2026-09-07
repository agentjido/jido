# Jido test instructions

Use `JidoTest.Case` for an isolated instance and `JidoTest.Eventually` for bounded
asynchronous assertions. Prefer barriers and process monitors to arbitrary waits.

Test complete candidate state, failure isolation, Turn order, Plugin ownership,
post-commit effects, persistence faults, remote lifecycle and resource cleanup.
Use deterministic model adapters or local HTTP/SSE for required examples.

Run `mix test test/jido test/jido_test --include flaky --seed 0` as the default
release check. CI uses this core-only selection. Example acceptance tests are
secondary; run `mix examples --seed 0` separately when needed.
Give every example test the `:example` tag, directly or through a
shared case template. Do not add an `:integration` tag. Keep runnable source in
`examples/`, assertions in `test/examples/`, and focused core tests in
`test/jido/`. Reuse fixtures; do not copy integration assertions between suites.
The DIST-03 test `one logical identity has at most one live cluster owner`
in `test/jido/agent/distributed_authority_test.exs` retains its approved skip.
The 11 known failing research tests listed in `test/examples/99_research/README.md`
are temporarily skipped. Each has a reason that names its missing feature.
Keep their assertions. Remove each skip when its feature is implemented.
Do not add other skips or exclude a group to hide a failure. A missing or empty
test selection is an error.

The runtime floor is Elixir 1.18 / OTP 27. Use Conventional Commits. Do not edit
`CHANGELOG.md`.
