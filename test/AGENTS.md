# Jido test instructions

Use `JidoTest.Case` for an isolated instance and `JidoTest.Eventually` for bounded
asynchronous assertions. Prefer barriers and process monitors to arbitrary waits.

Test complete candidate state, failure isolation, Turn order, Plugin ownership,
post-commit effects, persistence faults, remote lifecycle and resource cleanup.
Use deterministic model adapters or local HTTP/SSE for required examples.

Run `mix test --include example --include flaky --seed 0`.
CI runs `mix test test/jido test/jido_test test/examples/08_applications --include example --include flaky --seed 0`.
CI explicitly includes application examples. Run the rest of `test/examples`
separately. Give every example test the `:example` tag, directly or through a
shared case template. Do not add an `:integration` tag. Keep runnable source in
`examples/`, assertions in `test/examples/`, and focused core tests in
`test/jido/`. Reuse fixtures; do not copy integration assertions between suites.
Only the DIST-03 test `one logical identity has at most one live cluster owner`
in `test/jido/agent/distributed_authority_test.exs` can be skipped. Keep its
assertion and reason. Do not exclude a group to hide a failure. A missing or empty
acceptance selection is an error.

The runtime floor is Elixir 1.18 / OTP 27. Use Conventional Commits. Do not edit
`CHANGELOG.md`.
