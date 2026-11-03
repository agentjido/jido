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
| `agent_domain` | Agent data and authoring (`jido.agent`), pure evaluation (`jido.agent_evaluation`), references (`jido.agent_reference`), and the generic Plugin SDK (`jido.plugin`) |
| `live_runtime` | AgentServer (`jido.agent_server.*`), Instance (`jido.instance`), Persistence (`jido.persistence`), Signal delivery (`jido.signal.delivery`), and Telemetry (`jido.telemetry`) |
| `capabilities` | AI (`jido.ai.*`) and the bundled Audit, Bus, Heartbeat, Scheduler, and Sensor Manager components (`jido.plugin.*`) |
| `composition` | The OTP application (`jido.application`) and Catalog discovery (`jido.catalog.discovery`) |

The focused AgentServer components are `jido.agent_server`, `jido.agent_server.activation`, `jido.agent_server.effects`, `jido.agent_server.plugin_runtime`, `jido.agent_server.composition`, `jido.agent_server.durable`, `jido.agent_server.durable_turn`, and `jido.agent_server.handoff`.

The focused AI components are `jido.ai.agent_authoring`, `jido.ai.conversation`, `jido.ai.model_execution`, `jido.ai.observability`, `jido.ai.react`, `jido.ai.strategies`, `jido.ai.tools`, and `jido.ai.turn`. The bundled Plugin components are `jido.plugin.audit`, `jido.plugin.bus`, `jido.plugin.heartbeat`, `jido.plugin.scheduler`, and `jido.plugin.sensor_manager`.

`.reach.exs` is the source of truth for code dependency layers. Covenant is the source of truth for behavior ownership and proof. Each Covenant component owns modules from one Reach layer. Each module has no more than one primary Covenant owner. A component test can use a lower layer, but the component does not own that lower layer.

Some active Covenant IDs still start with `jido_action.` or `jido_ai.`. These are legacy IDs. Use the target `jido.*` IDs from `../docs/covenant-component-refactor-plan.md` for new architecture work.

## Work rules

- Run Mix commands from this directory.
- Keep one `:jido` OTP application. Keep `Jido.Application` as its only composition root.
- Change one namespace or Covenant component at a time. Change its tests and contract records in the same work.
- Update `../docs/aspirational-module-dependency-map.md` when ownership or dependency direction changes.
- Record a lasting architecture decision in `docs/adr/` and update its index.
- Run focused tests and `mix format --check-formatted` before handoff. For architecture changes, also run `mix reach.check --arch --smells` and the Covenant checks for the changed component.
- Do not edit generated files in `_build/`, `cover/`, or `deps/`.
