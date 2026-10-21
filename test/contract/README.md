# Covenant contracts

This directory is the one root for Covenant prose, decision records, survivor
ledgers, executable tests, and generated obligation coverage.

Earlier work put executable tests in `test/contract` and Covenant records in
`test/contracts`. That split made one component use two roots. All Covenant
files now use `test/contract`; do not recreate `test/contracts`.

The component register is in [`COMPONENTS.md`](COMPONENTS.md). A planned row is
not active until its obligation file and tagged tests pass together.

## Layout

Each component uses one directory. The directory name is the component ID.
Each directory contains `obligations.md`, `decisions.yml`, and, when needed,
`survivors.yml`. Tests stay in the same directory. A component with child
components keeps each child in a plain subdirectory. The parent component can
keep its tests in `core/`.

```text
test/contract/
  COMPONENTS.md
  coverage.json
  jido.agent/
    obligations.md
    decisions.yml
    survivors.yml
    *_test.exs
  jido.agent_evaluation/
    obligations.md
    decisions.yml
    survivors.yml
    *_test.exs
  jido.discovery/
  jido.error/
  jido.instance/
  jido.persistence/
  jido.signal_action/
  jido.telemetry/
  jido.plugin/
    obligations.md
    decisions.yml
    survivors.yml
    core/
    audit/
      obligations.md
      decisions.yml
      survivors.yml
    bus/
    heartbeat/
    scheduler/
    sensor_manager/
  jido.agent_server/
    README.md
    support.ex
    obligations.md
    decisions.yml
    core/
    activation/
      obligations.md
      decisions.yml
      survivors.yml
    composition/
    durable/
    durable_turn/
    effects/
    plugin_runtime/
```

The same record names apply to all component directories.

## Active boundaries

`jido.plugin` owns only the generic Plugin interface. Each bundled Plugin has
its own `jido.plugin.*` component. Agent evaluation and AgentServer runtime
behavior have separate owners.

`jido.plugin.scheduler` owns timer definitions, reconciliation, generations,
occurrence identity, clock rules, and future-timer recovery. It does not own
durable business delivery or acknowledgement.

`jido.agent` owns Agent values, authoring, validation, and logical composition.
It does not own AgentServer lifecycle, Directive dispatch, persistence stores,
or bundled Plugin behavior.

`jido.agent_evaluation` owns pure route selection, executable evaluation,
candidate validation, Plugin preparation and reduction, and returned
Directives. It does not own live AgentServer state or effect dispatch.

`jido.agent_server` owns core request, admission, Turn, cancellation,
failure-policy, and bounded observation behavior. Its mutation profile targets
`Jido.AgentServer.Core`. The public `Jido.AgentServer` state-machine
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

`jido.signal_action` owns the combined Action and Signal declaration, shared
input validation and conversion, input Signal construction, optional output
Signal contracts, reply validation, and reply correlation. It does not own
Action execution, Signal routing or dispatch, Agent route authoring, or
AgentServer commit timing.

`jido.discovery` owns the read-only Action catalog, scan sources, Action
admission, diagnostics, stable lookup indexes, filtering, paging, and complete
refresh replacement. It does not own Action execution, permission policy,
application allowlists, or Agent route discovery.

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
mix test.contract
```

This command runs `test/contract` and writes `test/contract/coverage.json`.
The reported percentage is obligation coverage, not code coverage.

Run mutation analysis at an explicit component review checkpoint:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --jobs 4 --seed 0 \
  --timeout 5000 --max-runtime 3600000
```

The Agent profile checks runtime and value modules. It does not mutate Spark
DSL declaration macros because invalid macro AST can stop the Elixir verifier
outside the test process. The authoring suite checks the generated DSL output.
