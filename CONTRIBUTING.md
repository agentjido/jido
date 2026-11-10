# Contributing to Jido

Jido is an Elixir framework for durable actors, Agents, Actions, Flows,
Signals, plugins, persistence, and AI capabilities.

## Development setup

Jido requires Elixir `~> 1.18` and OTP 27 or later.

```sh
git clone --branch migration/consolidated-v3 https://github.com/agentjido/jido.git
cd jido
mix deps.get
mix test
```

## Work rules

- Keep one `:jido` OTP application and one `Jido.Application` composition root.
- Keep dependency directions consistent with `.reach.exs`.
- Keep public tagged tuple and structured error contracts stable.
- Add or update tests in the same change as behavior.
- Use Conventional Commits.
- Do not edit `CHANGELOG.md`. The release process generates it.

## Required checks

Run the checks that match your change. Finish with the main offline gates.

```sh
mix format --check-formatted
mix test.ci
mix quality
```

Use the focused commands in [AGENTS.md](AGENTS.md) for authoring, property,
system, performance, service, and live-provider changes. External-service and
paid-provider checks require an approved test environment.

## Pull requests

Create consolidation work from `migration/consolidated-v3` until the V3
cutover is complete. Explain public or compatibility changes in the pull
request. Include the commands and results that prove the change.

See [the documentation index](docs/README.md), [the architecture map](docs/architecture/module-dependency-map.md), and [the usage rules](usage-rules.md) for more project context.
