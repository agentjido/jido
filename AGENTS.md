# Jido development instructions

Use ASD-STE100 Simplified Technical English. Do not use skills unless requested.

## Contract

- `Jido.Agent` holds complete domain state. A Signal selects one Action or Flow.
- Direct success is `{:ok, candidate, directives}`. Failure returns a structured error.
- Actions and Flows can perform I/O. A failed Turn preserves committed state; it cannot undo completed external work.
- `Jido.AgentServer` owns live state, serial Turns, admission, commit and effects.
- Keep the implemented Plugin callback order and Plugin state ownership.
- Use static Zoi schemas. Preserve structured errors at public boundaries.

## Checks

- Declared floor: Elixir 1.18 and OTP 27. Validate it during beta QA.
- Default quality check: `mix quality`. It runs fast core tests, not peer, benchmark, example, authoring, system, or service tests.
- Run filtered suites separately when needed: `mix test.peer`, `mix test.bench`, `mix test.examples`, `mix test.authoring`, and `mix test.system`.
- Run all six normal test categories with `mix test.all`. It includes local system tests, not external storage services.
- Run opt-in Redis, PostgreSQL and real Bedrock tests with `mix test.services`. Run the separate MinIO profile with `mix test.services.minio`. See `test/system/README.md` for prerequisites and storage limits.
- Compile with `mix compile --warnings-as-errors`.
- Keep coverage at or above 90%. Aim above 93% to retain a maintenance buffer.
- Run meaningful lint, Dialyzer, docs and package checks.
- See `test/AGENTS.md` and `guides/testing.md`.

## History

Use Conventional Commits. Do not edit `CHANGELOG.md`; release notes are generated.
Preserve donor history and published history.
