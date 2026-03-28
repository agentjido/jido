# Package

High-level package contract for Jido.

```spec-meta
id: package.jido
kind: package
status: active
summary: Jido is an Elixir framework for autonomous agent systems with pure agent logic and explicit runtime effects.
surface:
  - .dialyzer_ignore.exs
  - mix.exs
  - README.md
  - usage-rules.md
  - lib/jido.ex
  - lib/jido/agent.ex
  - lib/jido/agent_server.ex
```

## Requirements

```spec-requirements
- id: package.jido.framework
  statement: Jido shall provide an Elixir framework for autonomous agents, workflows, and multi-agent systems.
  priority: must
  stability: stable

- id: package.jido.pure_cmd
  statement: Jido shall treat agent modules as pure decision units whose core contract is cmd/2 returning an updated agent together with directives.
  priority: must
  stability: stable

- id: package.jido.runtime_separation
  statement: Jido shall keep runtime side effects explicit through directives and AgentServer runtime modules instead of hiding effects inside agent state transitions.
  priority: must
  stability: stable

- id: package.jido.local_quality_gate
  statement: Jido shall keep its repository-local quality tooling executable, including narrowly scoped analyzer suppressions for known external dependency issues when needed.
  priority: should
  stability: evolving
```

## Verification

```spec-verification
- kind: readme_file
  target: README.md
  covers:
    - package.jido.framework
    - package.jido.pure_cmd
    - package.jido.runtime_separation

- kind: contract
  target: usage-rules.md
  covers:
    - package.jido.pure_cmd
    - package.jido.runtime_separation

- kind: source_file
  target: .dialyzer_ignore.exs
  covers:
    - package.jido.local_quality_gate
```
