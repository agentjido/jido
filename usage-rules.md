# Jido Usage Rules

## Intent

Build reliable Agent systems. Keep decision logic pure. Keep runtime effects
explicit.

## Agent authoring

- Use `%Jido.Agent{}` as the one canonical Agent root.
- Use `Jido.Agent.new/1` or `new!/1` for inert definitions.
- Use `Jido.Agent.instantiate/2` for a definition that must become an instance.
- Use generated `MyAgent.agent/0` for the definition.
- Use generated `MyAgent.new/1` for normal module instance creation.
- Use generated `MyAgent.validate/2` only as the temporary state-validation shim.
- Use native data, Builder, the module DSL, or Codec documents to author the same definition.
- Use static named MFA callbacks in schemas. Do not use anonymous functions or closures.
- Do not select a strategy in new Agent authoring.

## Storage

- Store definitions through `Jido.Agent.Codec` and `Jido.Agent.Registry`.
- Let the caller own JSON encoding and decoding.
- Keep `id`, `state`, `agent_module`, and strategy data out of Codec documents.
- Use runtime persistence APIs for Agent instance state.

## Runtime

- Treat `cmd/2` as the core Agent contract: `{updated_agent, directives}`.
- Keep Agent logic pure. Directives describe external effects only.
- Use AgentServer and runtime modules for processes, timers, and delivery.
- Keep `jido` and `agent_module` as runtime or compile bindings only.
- Keep `category`, `tags`, and `vsn` as discovery or package metadata only.

## Plugins and routes

- Use canonical `Jido.Agent.Plugin` and `Jido.Agent.PluginDefaults` values.
- Use Actions for domain work.
- Use routes to select Actions for signals.
- Use `Directive.SpawnAgent` and `Directive.StopChild` for Agent hierarchy.
- Use signals for cross-Agent communication.

## Quality

- Start with pure `cmd/2` tests. Then add AgentServer integration tests.
- Use an isolated Jido instance for each runtime test.
- Prefer eventual assertions to fixed sleeps.
- Run `mix quality` and the full test suite before release.

## References

- `guides/agents.md`
- `guides/agent-builder.md`
- `guides/agent-storage.md`
- `guides/migration.md`
- `test/AGENTS.md`
- `AGENTS.md`
