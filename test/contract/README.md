# Covenant contracts

This directory is the one root for Covenant prose, decision records, survivor
ledgers, executable tests, and generated obligation coverage.

Earlier work put executable tests in `test/contract` and Covenant records in
`test/contracts`. That split made one component use two roots. All Covenant
files now use `test/contract`; do not recreate `test/contracts`.

The component register is in [`COMPONENTS.md`](COMPONENTS.md). A planned row is
not active until its obligation file and tagged tests pass together.

## Layout

Covenant uses `<app>/<component>.*` for contract records. Executable tests live
under the production namespace path. AgentServer subcomponent records use
`jido.agent_server/<component>.*`; their tests use
`jido/agent_server/<component>/`.

```text
test/contract/
  COMPONENTS.md
  coverage.json
  jido/
    agent.obligations.md
    agent/
    agent_evaluation.obligations.md
    agent_evaluation/
    discovery.obligations.md
    discovery.decisions.yml
    discovery.survivors.yml
    discovery/
    agent_server.obligations.md
    agent_server/
      activation/
      composition/
      durable/
      durable_turn/
      effects/
      plugin_runtime/
    instance.obligations.md
    instance/
    persistence.obligations.md
    persistence.decisions.yml
    persistence.survivors.yml
    persistence/
    plugin.obligations.md
    plugin/
    signal_action.obligations.md
    signal_action.decisions.yml
    signal_action.survivors.yml
    signal_action/
  jido.plugin/
    audit.obligations.md
    audit/
    bus.obligations.md
    bus/
    heartbeat.obligations.md
    heartbeat/
    scheduler.obligations.md
    scheduler/
    sensor_manager.obligations.md
    sensor_manager/
  jido.agent_server/
    activation.obligations.md
    activation.decisions.yml
    activation.survivors.yml
    composition.obligations.md
    composition.decisions.yml
    composition.survivors.yml
    durable.obligations.md
    durable.decisions.yml
    durable.survivors.yml
    durable_turn.obligations.md
    durable_turn.decisions.yml
    durable_turn.survivors.yml
    effects.obligations.md
    effects.decisions.yml
    effects.survivors.yml
    plugin_runtime.obligations.md
    plugin_runtime.decisions.yml
    plugin_runtime.survivors.yml
```

The matching `*.decisions.yml` and `*.survivors.yml` files stay beside each
obligation file.

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

## Gates

Run the complete obligation gate from the `jido` repository:

```sh
mix test.contract
```

This command runs `test/contract` and writes `test/contract/coverage.json`.
The reported percentage is obligation coverage, not code coverage.

Run mutation analysis at an explicit component review checkpoint:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros --jobs 4 --seed 0 \
  --timeout 5000 --max-runtime 3600000
```
