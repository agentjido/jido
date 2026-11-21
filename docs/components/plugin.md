---
title: Jido.Plugin component
status: current
last-reviewed: 2026-11-19
---

# Jido.Plugin component

This record covers the generic Plugin declaration, initialization, and host
contract at [`6fdc009a1edd6261f3e26509fa2905bb9192faa5`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5)
on `release/v3`. All four review checks have evidence. This component's
implementation covers #470, #471, #473, #474, and #475. The Agent review
owns the provider authoring boundary under #483.
[Tracker #453](https://github.com/agentjido/jido/issues/453)
[Agent issue #483](https://github.com/agentjido/jido/issues/483)

## Public surface

`use Jido.Plugin` defines a capability and an Agent authoring provider in one
module. Its options are `id`, `vsn`, `sections`, `imports`, and
`option_keys`. The module name and version 1 are the default identity. Agent
DSL accepts a Plugin module or `{module, config_map}`. Data definitions store
one contribution with `id`, `provider`, `vsn`, and `data`. The config map
has atom keys and static values. An authoring-only provider can contribute
data and routes without a runtime marker.
[Behavior and macro](../../lib/jido/plugin.ex#L17-L43)
[Agent declaration](../../lib/jido/agent/plugin/declaration.ex#L7-L36)
[Provider validation](../../lib/jido/agent/extension.ex#L165-L188)

| Owner | Optional callbacks and results |
| --- | --- |
| Agent | `prepare/2` and `reduce/2` return `{:ok, value}` or `{:error, reason}`. `select_route/2` also accepts `:default` and can select one declared matching route. `state_spec/1` declares no state or one atom field with a static Joi schema. `directives/1` declares the owned Directive modules. Both declaration callbacks can return an error. A Joi schema in `{:error, schema}` declares the field `:error`. |
| AgentServer | `validate_options/1`, `await_ready/2`, `after_commit/3`, and `dispatch/4` return `:ok` or an error. `admit/3` returns transient input or an error. `prepare_outbound/4` returns a validated Signal or an error. `child_spec/1` receives an Init and returns a permanent OTP child specification. `await_ready/2` requires `child_spec/1`. |
| Persistence | `dump/3` and `load/3` form a pair. They return `{:ok, value}` or `{:error, reason}` for the owned state field. |

`Input` keeps portable prepared input and transient runtime input separate.
The public handoff records are `Init`, the phase-tagged `Context`, and the
Admission, Commit, and Persistence contexts. `Init` gives a runtime generation
the activation-local server handle, Agent identity, owned value and revision,
instance, partition, and AgentServer options. `Jido.Plugin.Config.env/1` creates
a deferred environment reference. The runtime calls `resolve/1` to read it.
Errors preserve the path without copying the complete config.
[Init](../../lib/jido/plugin/init.ex)
[Configuration](../../lib/jido/plugin/config.ex)
[Public API tests](../../test/jido/plugin/api_test.exs)
[Context tests](../../test/jido/plugin/context_test.exs)

Manifest, Normalizer, Spec, and callback error helpers are internal. Owners
receive keyword options. The default supplies the same declaration options
to every selected owner. An explicit `option_keys` map limits what each owner
receives. Runtime overrides can add transient values to exclusive AgentServer
options for a matching Plugin. The normalizer revalidates the merged options.
It leaves common, Agent, and persistence options intact. Existing tests
establish that shared runtime options for an absent Plugin are ignored.
[Manifest](../../lib/jido/plugin/manifest.ex#L27-L64)
[Runtime binding](../../lib/jido/plugin/normalizer.ex#L31-L143)
[Runtime option tests](../../test/jido/plugin/validation_test.exs#L315-L355)

## API contract usage

- Agent definition composes the domain schema with validated Plugin-owned
  fields. The Agent prepares input before route choice. Its pipeline validates
  Directives and protects owned state before it runs the reducers. The ordering
  tests cover first failure, later reducer failure, and separate input values.
  [Agent schema](../../lib/jido/agent/validation.ex#L333-L349)
  [Preparation and routing](../../lib/jido/agent/plugin.ex#L88-L133)
  [Reduction pipeline](../../lib/jido/agent/plugin/pipeline.ex#L16-L44)
  [Ordering tests](../../test/jido/plugin/ordering_test.exs)
- AgentServer uses the normalized runtime options for startup, admission,
  outbound Signal preparation, and post-commit effects. The readiness check
  receives the live root. Commit hooks run in declaration order before
  Directive dispatch. Outbound preparation runs in reverse declaration order.
  [Host initialization](../../lib/jido/agent_server/plugin.ex#L25-L65)
  [Host callbacks](../../lib/jido/agent_server/plugin/callbacks.ex)
  [Runtime rules tests](../../test/jido/agent_server/plugin_runtime/rules_test.exs)
- Persistence uses the Agent and Persistence Specs together. It converts only
  the owned state field. It checks format context, portable storage values, and
  the Joi schema after load. The tests cover paired conversion, foreign
  contexts, and rejected loaded values.
  [Checkpoint conversion](../../lib/jido/persistence/checkpoint.ex#L59-L89)
  [Persistence Plugin boundary](../../lib/jido/persistence/plugin.ex#L14-L55)
  [Persistence integration](../../test/jido/persistence/plugin_integration_test.exs)
- The bundled Plugins and Jido AI use the same declaration contract. This
  pass used their declarations and integration tests as consumer evidence.
  [AI Plugin contract test](../../test/jido/ai/agent/agent_plugin_contract_test.exs)
  [Plugin authoring tests](../../test/jido/plugin/authoring_test.exs)
  [Covenant obligations](../../test/contracts/jido/plugin.obligations.md)

## Code quality

The Plugin macro now uses the Extension's shared defaults for `normalize/1`
and `verify/2`. Tests cover overrides, `super` calls, plain-map and static-data
validation, default results, and authoring-only providers. The numbered
authoring extension example uses those same callbacks.
[#475](https://github.com/agentjido/jido/issues/475)
[Plugin defaults](../../lib/jido/plugin.ex#L119-L145)
[Extension defaults](../../lib/jido/agent/extension.ex#L61-L90)

The production caller search found `Normalizer.canonical_declarations/1`
and `Normalizer.declarations/1` in tests and Covenant only. The first builds
or validates a full Spec. The second can inspect declaration syntax without
loading callbacks. This pass retains their current Covenant rules. Tests
establish that reuse checks static structure without repeating declaration
callbacks. These checks also preserve exact owner options, list order, and the
distinction between raw declarations and normalized Specs.
[Normalizer paths](../../lib/jido/plugin/normalizer.ex#L60-L82)
[Reuse tests](../../test/jido/plugin/normalizer_test.exs#L182-L246)

## Elixir and OTP design

Keep one Elixir behavior with optional callbacks and one declaration per
Plugin. The compiler derives owner membership from a fixed name and arity
list. The normalizer checks callback ownership and pairings before handing
narrow Specs to Agent, AgentServer, and Persistence. Preserve the separate
portable and live inputs, one owned state field, and the host's commit
authority. Runtime processes belong to the activation's Plugin supervisor.
A failed runtime root triggers group recovery. A worker restart keeps healthy
roots and the stable activation handle. A replacement root builds its Init
from the current committed field and revision. The live state accessor belongs
to `jido.agent_server.plugin_runtime`.
[Owner discovery](../../lib/jido/plugin.ex#L100-L175)
[Child start](../../lib/jido/agent_server/plugin.ex#L128-L171)
[Activation supervisor](../../lib/jido/agent_server/supervisor.ex#L48-L71)
[Recovery test](../../test/jido/agent_server/durable_activation_contract_test.exs#L574-L622)

The AgentServer review owns startup orchestration. A probe observed two
`child_spec/1` calls for one initial runtime start with the same revision and
options. The first validates the child metadata. The supervisor wrapper calls
it again to use a fresh Init. Worker startup also normalizes the same
declarations at several boundaries. Review those calls with the host's
recovery order, error propagation, and fresh Init requirements. Audit, Bus,
Timer, Sensor Manager, and Agent Plugin FSM remain separate reviews.
[Bootstrap and root start](../../lib/jido/agent_server/plugin.ex#L25-L43)
[Worker start options](../../lib/jido/agent_server/worker.ex#L154-L169)
[Worker initialization](../../lib/jido/agent_server/worker.ex#L762-L769)

## Confirmed defects

| Severity | Finding and observed impact | Issue |
| --- | --- | --- |
| P2 | A Plugin with only `await_ready/2` was accepted. The server returned `:ok` without calling the hook. The same hook with a runtime root blocked readiness. Require `child_spec/1` when a Plugin defines `await_ready/2`. | [#470](https://github.com/agentjido/jido/issues/470) |
| P2 | A reducer Plugin with `directives/1` returning `[nil]` acquired a nil owner entry. An improper list from the same callback raised from `Agent.define/1`. Reject both results with a structured Plugin error. | [#471](https://github.com/agentjido/jido/issues/471) |
| P2 | A raising ID escaped `Agent.define/1`. A throwing or exiting authoring `normalize/1` also escaped. The direct normalizer contained the ID failure. Apply fault containment to the public authoring path. | [#472](https://github.com/agentjido/jido/issues/472) closed as a duplicate of [#483](https://github.com/agentjido/jido/issues/483) |
| P3 | `state_spec/1` returning `{:error, :probe_rejected}` produced a generic invalid-result error. An exception reason passed through. Keep `:error` as a valid owned key when it has a Joi schema. | [#473](https://github.com/agentjido/jido/issues/473) |
| P3 | The Supervised Resources startup cell raised when it received the current TurnResult. The recovery cell calls a removed function and uses an old child location. Use the current public startup, result, and recovery contract. | [#474](https://github.com/agentjido/jido/issues/474) |

Each issue gives pinned source links and acceptance checks.

## Implementation evidence

- Regression tests failed before the fix for readiness without a runtime,
  nil Directive ownership, an improper Directive list, and a lost state
  rejection reason. The tests also cover direct normalization and Agent
  definition. The readiness and Directive tests cover reused Specs.
- The authoring override test passed before the cleanup. It checks the
  default results and the results of calling `super` from both callbacks.
  The focused suite passed 199 tests after the changes.
- The Supervised Resources guide uses the public Turn result and snapshot
  APIs. It locates the Plugin's own process through a Registry and checks
  the replacement Init value and revision. The tutorial cells passed with
  the documented startup, recovery, and runtime option results.

## Verification for the parent review

- The focused suite passed 154 tests. With integration enabled, the generic
  Plugin files, Agent declaration, AgentServer Plugin runtime rules, Plugin
  persistence, AI Plugin contract, and examples for Plugin authoring and state
  conversion passed 177 tests.
- The targeted test at line 575 of the durable activation suite passed. The
  full durable activation file ran in a 191-test command. The exact terminal
  result test at line 313 and concurrent Address delivery test at line 490
  timed out. Both timed out again in an isolated rerun and remain with the
  AgentServer review.
  [Durable activation suite](../../test/jido/agent_server/durable_activation_contract_test.exs)
- Temporary probes exercised the public `Agent.define/1` and AgentServer
  startup paths. The Supervised Resources guide ran through its expected
  missing-prefix example. Its first live call returned a committed
  `TurnResult` and raised when the cell matched the old result shape.
- `mix format --check-formatted` and `git diff --check` passed.

## Audit sub-component

`Jido.Plugin.Audit` creates portable Audit records and reduces them into one
bounded `:audit` field. It has no process. Record order and `max_entries` are
part of its public contract.

Result: Retain it as one pure sub-component. It does not overlap Telemetry,
because Audit records are committed domain state.

## Bus sub-component

The Bus capability has three public entries:

- `Jido.Plugin.Bus.Manager` owns one local `Jido.Signal.Bus` process.
- `Jido.Plugin.Bus.Client` subscribes an Agent to a Bus.
- `Jido.Plugin.Bus.DSL` adds static Bus endpoints to Agent authoring.

Manager and Client are separate Plugin packages, but they form one integration
capability. Manager can host a Bus without a Client. Client can connect to a
Bus that another owner hosts. The shared Covenant owner covers local ownership,
subscription, reconnect, delivery, durable acknowledgement, and retry.

Result: Keep one checklist sub-component with the three explicit public entry
modules. Do not add an empty `Jido.Plugin.Bus` facade.

## Timer sub-component

`Jido.Plugin.Timer` owns delayed and recurring Signal definitions. Public
Schedule, Cron, Every, Pause, Resume, and Cancel Directives control it. Static
Agent options can create one auto-start interval. Occurrence data gives a
stable identity to a generated tick. A DeliveryAdapter can move cron delivery
to an external system.

The runtime reconciles committed recurring state, fences old revisions, tracks
one-shot timers outside Agent state, retries failed reconciliation, and restores
future jobs after replacement.

Result: Retain it as the only bundled timer sub-component. Durable business
delivery, acknowledgement, and queue storage stay outside it.

## Sensor Manager sub-component

`Jido.Plugin.SensorManager` owns a portable desired sensor map. Start and Stop
Directives update that map. A Supervisor and controller reconcile live sensor
children to the committed value. Revision fencing and one retry timer prevent
old work from replacing new work.

Result: Retain it as one supervised-input sub-component. Sensor behavior and
Signal handling stay with the sensor and Agent.

## Previous sub-component evidence

The 2026-11-13 focused command ran the complete `test/jido/plugin` tree as part
of a 502-test command. All tests passed. The review also traced the generic
Plugin Covenant owner and the focused Audit, Bus, Timer, and Sensor Manager
Covenant owners.

The review did not run real external Bus or Timer adapters. It made no
production change.

## Sources

- [Plugin behavior](../../lib/jido/plugin.ex)
- [Plugin normalizer](../../lib/jido/plugin/normalizer.ex)
- [Audit](../../lib/jido/plugin/audit.ex)
- [Bus Manager](../../lib/jido/plugin/bus/manager.ex)
- [Bus Client](../../lib/jido/plugin/bus/client.ex)
- [Timer](../../lib/jido/plugin/timer.ex)
- [Sensor Manager](../../lib/jido/plugin/sensor_manager.ex)
- [Plugin obligations](../../test/contracts/jido/plugin.obligations.md)
