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
- Full suite: `mix test --include example --include integration --include flaky`.
- Compile with `mix compile --warnings-as-errors`.
- Keep coverage at 80%. Run meaningful lint, Dialyzer, docs and package checks.
- See `test/AGENTS.md` and `docs/migration/08-execution-goal.md`.

## History

Use Conventional Commits. Do not edit `CHANGELOG.md`; release notes are generated.
Keep migration commits local. Preserve the pinned donor inputs and published history.
