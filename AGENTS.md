# Jido

## Product

Jido is an Elixir SDK for durable OTP actors and Agents. It gives developers one model for state, messages, behavior, effects, persistence, observation, and AI.

An Agent contains a portable definition and immutable state. A Signal starts a Turn. A Flow defines the Turn behavior, and Actions are its work units. The Flow returns candidate state and Directives. AgentServer serializes Turns, validates and commits state, and then runs effects. It also owns waits, recovery, timers, and process lifecycle.

OTP owns process lifecycle and failure. Jido keeps domain decisions in explicit data. Plugins add complete capabilities. AI is a first-party Plugin capability, not a separate runtime.

## Architecture

Dependencies point left through the Reach layers:

```text
primitives <- value_model <- definitions <- execution <- agent_domain <- live_runtime <- capabilities <- composition
```

Use these major components and target Covenant IDs:

| Reach layer | Major components |
|---|---|
| `primitives` | Identity (`jido.id`), validation (`jido.joi`), expressions (`jido.expr`), errors (`jido.error`), trace data (`jido.trace`), and base codecs (`jido.codec.compiler`, `jido.codec.term`) |
| `value_model` | Signals (`jido.signal`), Catalog (`jido.catalog`), Session and Thread values (`jido.conversation`), and portable values and references (`jido.codec`) |
| `definitions` | Actions (`jido.action`, `jido.action.inline`, `jido.action.output`, `jido.action.validation`), Flows (`jido.flow`, `jido.flow.inline`), Instructions (`jido.instruction`), Plugin definitions (`jido.plugin.definition`), and Signal routing (`jido.signal.routing`) |
| `execution` | Flow execution (`jido.execution`) and the Action execution boundary (`jido.execution.action_boundary`) |
| `agent_domain` | Agent data and authoring (`jido.agent`), pure evaluation (`jido.agent_evaluation`), addresses (`jido.agent_reference`), and the generic Plugin SDK (`jido.plugin`) |
| `live_runtime` | AgentServer (`jido.agent_server.*`), Instance (`jido.instance`), Persistence (`jido.persistence`), Signal delivery (`jido.signal.delivery`), and Telemetry (`jido.telemetry`) |
| `capabilities` | AI (`jido.ai.*`) and the bundled Audit, Bus, Heartbeat, Scheduler, and Sensor Manager components (`jido.plugin.*`) |
| `composition` | The OTP application (`jido.application`) and Catalog discovery (`jido.catalog.discovery`) |

The focused AgentServer components are `jido.agent_server`, `jido.agent_server.activation`, `jido.agent_server.effects`, `jido.agent_server.plugin_runtime`, `jido.agent_server.composition`, `jido.agent_server.durable`, `jido.agent_server.durable_turn`, and `jido.agent_server.handoff`.

The focused AI components are `jido.ai.agent_authoring`, `jido.ai.conversation`, `jido.ai.model_execution`, `jido.ai.observability`, `jido.ai.react`, `jido.ai.strategies`, `jido.ai.tools`, and `jido.ai.turn`. The bundled Plugin components are `jido.plugin.audit`, `jido.plugin.bus`, `jido.plugin.heartbeat`, `jido.plugin.scheduler`, and `jido.plugin.sensor_manager`.

`.reach.exs` is the source of truth for code dependency layers. Covenant is the source of truth for behavior ownership and proof. Each Covenant component owns modules from one Reach layer. Each module has no more than one primary Covenant owner. A component test can use a lower layer, but the component does not own that lower layer.

Some active Covenant IDs still start with `jido_action.` or `jido_ai.`. These are legacy IDs. Use `jido.*` IDs for new architecture work and update the component contracts in the same change.

## Work rules

- Run Mix commands from this directory.
- Keep one `:jido` OTP application. Keep `Jido.Application` as its only composition root.
- Change one namespace or Covenant component at a time. Change its tests and contract records in the same work.
- Update `docs/architecture/module-dependency-map.md` when ownership or dependency direction changes.
- Record a lasting architecture decision in `docs/adr/` and update its index.
- Run focused tests and `mix format --check-formatted` before handoff. For architecture changes, also run `mix reach.check --arch --smells` and the Covenant checks for the changed component.
- Run `mix test.authoring` for public authoring compatibility and `mix test.contracts` for all Covenant contracts. Both commands run in `mix test.ci`.
- Do not edit generated files in `_build/`, `cover/`, or `deps/`.

## Change verification matrix

Run the focused command for every changed surface. Run more than one command
when a change crosses rows. `mix test.all` is the complete offline test alias.
It does not select live provider or external-service tests.

| Change type | Required focused command |
|---|---|
| Unit behavior | The narrow `mix test path/to/test.exs`, then `mix test` |
| Public DSL, JSON, codec, or authoring | `mix test.authoring` |
| Supported numbered example | `mix test.examples` |
| Generated invariant or public API fuzz surface | `mix test.property` and `mix test.fuzz` |
| Runtime, persistence, recovery, or process cleanup | The focused runtime tests and, when applicable, `mix test.peer` |
| Concurrency, ownership, or sustained execution | `mix test.load` |
| Benchmark runner or metric | `mix test.bench`, then the changed documented `mix bench.*` command |
| Covenant component behavior | `mix test.contracts` |
| Namespace, dependency direction, or architecture | `mix reach.check --arch --smells` |
| External adapter | The documented `mix test.services` target with a dedicated test service |
| Live AI provider | `mix test.live` with `JIDO_LIVE_OPENAI_API_KEY` set to an approved test key |

Always finish with `mix format --check-formatted`. Use `mix test.ci` or
`mix test.all` before a full handoff. Use `mix quality` for the static quality
gate. The gate fails on highest-priority Credo findings. It also prints the
full strict Credo backlog as advisory output. Compile warnings, Dialyzer,
ExDNA, and Reach remain blocking. Dialyzer uses the line-specific checked-in
baseline in `.dialyzer_ignore.exs` and fails when an entry becomes unused.
ExDNA reports every clone and fails when the current 17-clone brownfield
baseline increases.
