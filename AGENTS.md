# AGENTS.md - Jido Guide

## Intent
Build reliable agent systems by separating pure decision logic from runtime side-effect execution.

## Runtime Baseline
- Elixir `~> 1.18`
- OTP `27+` (release QA baseline)

## Commands
- `mix test` (default alias excludes `:flaky`)
- `mix test --include flaky` (full suite)
- `mix test --cover` (coverage gate)
- `mix q` or `mix quality` (`format --check-formatted`, `compile --warnings-as-errors`, `credo`, `dialyzer`)
- `mix docs` (local docs)

## Architecture Snapshot
- `Jido.Agent`: pure agent module with immutable state and `cmd/2`
- `Jido.AgentServer`: GenServer runtime for directives, lifecycle, and message flow
- `Jido.Agent.Directive.*`: typed effect descriptors (`Emit`, `SpawnAgent`, `StopChild`, etc.)
- `Jido.Agent.StateOp.*`: internal state transition operations applied by strategy layer
- Plugins/sensors provide capability composition without coupling core agent logic

## Standards
- Keep `cmd/2` pure: same input => same `{agent, directives}` output
- Keep directives for external effects only; do not rely on directives for state mutation
- Use **Zoi-first** schemas for new agent/plugin/signal contracts
- Preserve tagged tuple and structured error contracts at public boundaries
- Keep cross-agent communication on signals/directives, not ad-hoc process messages

## Testing and QA
- Prefer pure agent tests first, then AgentServer/runtime integration tests
- Use helpers from `test/AGENTS.md` (`JidoTest.Case`, `JidoTest.Eventually`) for async assertions
- Avoid `Process.sleep/1` in tests; assert eventual state/event behavior

## Release Hygiene
- Keep semver ranges stable (`~> 2.0` for Jido ecosystem peers)
- Use Conventional Commits
- Update `CHANGELOG.md`, guides, and examples for behavior/API changes

## References
- `README.md`
- `usage-rules.md`
- `guides/`
- `test/AGENTS.md`
- https://hexdocs.pm/jido
