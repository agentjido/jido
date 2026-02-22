# Jido Usage Rules

## Intent
Build reliable multi-agent systems by keeping decision logic pure and runtime effects explicit.

## Core Contracts
- Treat `cmd/2` as the core agent contract: `{updated_agent, directives}`.
- Keep agent logic pure; directives describe external effects only.
- Use **Zoi-first** schemas for new agents, directives, plugins, and signals.
- Preserve tagged tuple and structured error contracts at public boundaries.
- Use AgentServer/runtime modules for process concerns, not agent module internals.

## Library Author Patterns
- Author actions for domain behavior; let agents orchestrate state + directive emission.
- Use `Directive.SpawnAgent` / `Directive.StopChild` for hierarchy, not ad-hoc child tracking.
- Use signals for cross-agent communication instead of direct process coupling.
- Keep plugin/sensor concerns isolated and composable.

## QA Patterns
- Start with pure `cmd/2` tests, then add AgentServer integration tests.
- Use `JidoTest.Case` + `JidoTest.Eventually` for async runtime assertions.
- Run `mix q` (`mix quality`) and coverage checks before release.

## Avoid
- Embedding runtime side effects directly in core state transition code.
- Using directives as a hidden state-mutation mechanism.
- Tight coupling between unrelated agent modules.

## References
- `README.md`
- `guides/`
- `test/AGENTS.md`
- `AGENTS.md`
- https://hexdocs.pm/jido
- https://hexdocs.pm/usage_rules/readme.html#usage-rules
