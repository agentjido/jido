# Jido test instructions

Use `JidoTest.Case` for an isolated instance and `JidoTest.Eventually` for bounded
asynchronous assertions. Prefer barriers and process monitors to arbitrary waits.

Test complete candidate state, failure isolation, Turn order, Plugin ownership,
post-commit effects, persistence faults, remote lifecycle and resource cleanup.
Use deterministic model adapters or local HTTP/SSE for required examples.

Run `mix test --include example --include integration --include flaky --seed 0`.
Only the exact DIST-03 test in the migration manifest can be skipped. Keep its
assertion and reason. Do not exclude a group to hide a failure. A missing or empty
acceptance selection is an error. Source results do not prove core acceptance.

The runtime floor is Elixir 1.18 / OTP 27. Use Conventional Commits. Do not edit
`CHANGELOG.md`.
