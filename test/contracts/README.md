# Covenant contracts

This directory is the one root for Covenant obligations, decision records,
survivor ledgers, and generated obligation coverage. Executable tests can stay
in their feature test directories. They bind to a component with
`Covenant.Case`.

## Component register

Status: The current components are active. Reach realignment is prepared and
is not yet complete.

The target component IDs start with `jido.`. Some active IDs still start with
`jido_action.` or `jido_ai.`. The realignment will replace those legacy package
names. Durable behavior stays under the `jido.agent_server` boundary.

A component is active only when it has an `obligations.md` file and passing
tests with its obligation tags.

| Component | Purpose | Contract area |
| --- | --- | --- |
| `jido.instance` | Jido instance supervision, namespace, options, and Ref routing | `test/contracts/jido/instance.*` |
| `jido.agent` | Agent model, authoring, validation, logical topology, and edits | `test/contracts/jido/agent.*` |
| `jido.agent_evaluation` | Pure Agent evaluation and candidate production | `test/contracts/jido/agent_evaluation.*` |
| `jido.agent_server` | Transient serialized Turn lifecycle | `test/contracts/jido/agent_server.*` |
| `jido.agent_server.activation` | Activation root, readiness, identity, and local recovery | `test/contracts/jido.agent_server/activation.*` |
| `jido.agent_server.effects` | Ordered post-commit effects | `test/contracts/jido.agent_server/effects.*` |
| `jido.agent_server.plugin_runtime` | Live generic Plugin hosting | `test/contracts/jido.agent_server/plugin_runtime.*` |
| `jido.agent_server.composition` | Runtime child and connection resources | `test/contracts/jido.agent_server/composition.*` |
| `jido.agent_server.durable` | Persistence-backed AgentServer state coordination | `test/contracts/jido.agent_server/durable.*` |
| `jido.agent_server.durable_turn` | Durable Flow progress, waits, and receipts | `test/contracts/jido.agent_server/durable_turn.*` |
| `jido.persistence` | Records, snapshots, adapters, storage operations, and revisions | `test/contracts/jido/persistence.*` |
| `jido.plugin` | Generic Plugin SDK and callback contracts | `test/contracts/jido/plugin.*` |
| `jido.telemetry` | Telemetry, metrics, tracing, logs, and Debug support | `test/contracts/jido/telemetry.*` |
| `jido.error` | Shared error taxonomy and stable common codes | `test/contracts/jido/error.*` |
| `jido.plugin.audit` | Bundled Audit Plugin behavior | `test/contracts/jido.plugin/audit.*` |
| `jido.plugin.bus` | Bundled Bus Plugin behavior | `test/contracts/jido.plugin/bus.*` |
| `jido.plugin.heartbeat` | Bundled Heartbeat Plugin behavior | `test/contracts/jido.plugin/heartbeat.*` |
| `jido.plugin.scheduler` | Bundled Scheduler Plugin behavior | `test/contracts/jido.plugin/scheduler.*` |
| `jido.plugin.sensor_manager` | Bundled SensorManager Plugin behavior | `test/contracts/jido.plugin/sensor_manager.*` |

### Dependency rules

- `jido.agent_server` uses `jido.agent_evaluation` and its AgentServer
  subcomponents.
- `jido.agent_server.activation` uses `jido.instance`.
- `jido.agent_server.durable` and `jido.agent_server.durable_turn` use
  `jido.persistence`.
- Each `jido.plugin.*` bundled component uses `jido.plugin`.
- `jido.agent_evaluation` uses `jido.agent` and `jido.plugin`.
- `jido.telemetry` is best effort. An observation failure must not change
  consumer behavior.
- Each Covenant component owns modules from one Reach layer.
- A test can use lower Reach layers, but their modules do not enter the
  component's `modules:` ownership list.
- Each module has no more than one primary Covenant owner.

### Component change rules

1. Define obligations from supported behavior.
2. Move or split existing tagged tests. Do not copy complete suites.
3. Select behavior-bearing mutation targets with no unexplained overlap.
4. Activate a new component and retire the replaced obligation in the same
   change.
5. Keep production code line count neutral or lower during extraction.

See the
[`Covenant and Reach realignment plan`](../../../docs/covenant-component-refactor-plan.md)
for the current audit, target register, and execution order.

## Layout

The configured record root is `test/contracts`. A component uses an
`obligations.md` file, a `decisions.yml` file, and, when needed, a
`survivors.yml` file. Tests can stay in any configured `test_paths` directory.

```text
test/contracts/
  README.md
  coverage.json
  jido/
    agent.obligations.md
    agent.decisions.yml
    agent.survivors.yml
    agent_evaluation.obligations.md
    error.obligations.md
    instance.obligations.md
    persistence.obligations.md
    plugin.obligations.md
    telemetry.obligations.md
  jido.plugin/
    audit.obligations.md
    bus.obligations.md
    heartbeat.obligations.md
    scheduler.obligations.md
    sensor_manager.obligations.md
  jido.agent_server/
    activation.obligations.md
    composition.obligations.md
    durable.obligations.md
    durable_turn.obligations.md
    effects.obligations.md
    plugin_runtime.obligations.md
  jido_action/
    ...legacy component records pending realignment...
  jido_ai/
    ...legacy component records pending realignment...
```

The first directory segment and the record name form the component ID. For
example, `jido.agent_server/effects.obligations.md` defines
`jido.agent_server.effects`.

## Active boundaries

`jido.plugin` owns only the generic Plugin interface. Each bundled Plugin has
its own `jido.plugin.*` component. Agent evaluation and AgentServer runtime
behavior have separate owners.

`jido.plugin.scheduler` owns timer definitions, reconciliation, generations,
occurrence identity, clock rules, and future-timer recovery. It does not own
durable business delivery or acknowledgement.

`jido.agent` owns Agent definitions and instances, state schemas, the Agent
DSL, logical topology, extension contributions, definition mutation and Diff
data, the Agent document codec adapter, and safe Agent views. It uses shared
Codec, Registry, Document, Value, and Discovery behavior from
`jido_action`. It does not own pure evaluation, Agent references, AgentServer
lifecycle, Directive dispatch, persistence, or bundled Plugin runtime behavior.

`jido.agent_evaluation` owns pure route selection, executable evaluation,
candidate validation, Plugin preparation and reduction, and returned
Directives. It does not own live AgentServer state or effect dispatch.

`jido.agent_server` owns core request, admission, Turn, cancellation,
failure-policy, and bounded observation behavior. Its mutation profile targets
`Jido.AgentServer.Lifecycle`. The public `Jido.AgentServer` state-machine
coordinator is covered through public contract tests and the focused profiles
of each AgentServer behavior owner.

`jido.agent_server.activation` owns the local OTP root, selected instance
registration, readiness publication, worker replacement, local checkpoints,
activation control records, and activation-owned child records. It does not
own Turn evaluation, durable storage, Plugin callback rules, or child behavior.

`jido.agent_server.effects` owns complete effect-batch admission, the
post-commit caller boundary, ordered Directive work, effect deadlines and task
settlement, outbound Signal preparation, built-in runtime Directives, and safe
post-commit error reporting. It does not own the commit, Plugin root behavior,
runtime child restart policy, or durable storage.

`jido.agent_server.plugin_runtime` owns live Plugin readiness, admission,
post-commit callbacks, outbound Signal preparation, Plugin Directive dispatch,
and safe live Plugin replacement. It does not own the generic Plugin SDK,
Agent evaluation, the commit, or durable storage.

`jido.agent_server.composition` owns child relationships, adoption, accepted
topology member reconciliation, local topology Buses, connection delivery, and
runtime child lifetime. It does not own pure topology validation, Plugin
callbacks, durable storage, or Turn evaluation.

`jido.agent_server.durable` owns explicit create and restore, required Agent
saves, durable recovery authority, portable save use, hibernation, persistent
idle policy, live snapshots, and upgrade coordination. It does not own record
formats, local checkpoints, or durable Flow progress and receipts.

`jido.agent_server.durable_turn` owns saved Flow Turn receipts, Runic graph
checkpoints, wait input receipts, wait resolution, Worker suspension, and
recovery of one persistent Flow execution. It does not own Agent record
formats, general Agent commits, transient Turn execution, or post-commit
effects.

`jido.persistence` owns adapter configuration, stable durable identity,
portable Agent records and snapshots, Plugin-owned state conversion,
revisions, tombstones, and built-in adapter conformance. It does not own live
AgentServer recovery, commit publication, durable Flow progress, or
backend-specific maintenance.

`jido.telemetry` owns the fixed metric catalog, semantic event lifecycle, safe
fields, bounded logs, per-instance Debug overrides, W3C trace context, and
optional OpenTelemetry mapping. It does not own the runtime or persistence
operations that emit events, reporter configuration, OpenTelemetry SDK startup,
sampling, export, or durable audit records.

`jido.error` owns the shared taxonomy, constructors, common-code registry,
retry classification, and bounded version-1 projection. It does not own Agent
or Plugin errors, domain failure conversion, adjacent-package error types, or
runtime retry and recovery policy.

## Gates

Run the complete obligation gate from the `jido` repository:

```sh
mix covenant.check
```

This command runs the configured test paths and writes
`test/contracts/coverage.json`.
The reported percentage is obligation coverage, not code coverage.

Run mutation analysis at an explicit component review checkpoint:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --jobs 4 --seed 0 \
  --timeout 5000 --max-runtime 3600000
```

The Agent profile checks runtime and value modules. It does not mutate Spark
DSL declaration macros because invalid macro AST can stop the Elixir verifier
outside the test process. The authoring suite checks the generated DSL output.
