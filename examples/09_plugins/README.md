# Plugin examples

Plugins can extend Agent authoring and execution. A Plugin can add a domain
language to the Agent DSL, validate its data, own state, and manage runtime
resources. These are parts of one extension contract.

## Learning order

1. [Prepared Input](09_01_prepared_input/README.md) — derive portable input from the incoming Signal.
2. [Runtime Admission](09_02_runtime_admission/README.md) — derive transient input from private runtime state.
3. [State Middleware](09_06_state_middleware/README.md) — read the complete candidate and reduce one owned field.
4. [Plugin DSL](09_10_plugin_dsl/README.md) — add a section and named entities to Agent syntax; use the same Plugin through Map and JSON authoring.
5. [Composition](09_05_composition/README.md) — combine pure and live inputs in one Agent.
6. [Live Plugin Changes](09_09_live_plugin_changes/README.md) — change runtime options and restore the accepted Plugin after hibernation.
7. [Identity](09_03_identity/README.md) — combine signature checks with live replay protection.
8. [Secure Signal](09_04_secure_signal/README.md) — decrypt input and encrypt output in Plugin order.

Numbers are stable IDs. Use this reading order. Each lesson keeps its teaching
code local. Small copies of input and identity Plugins make the composition
lessons readable without opening an earlier lesson. Cryptographic primitives
remain in [shared support](support/crypto.ex).

## Run the section

```sh
mix test test/examples/09_plugins --include example --seed 0
```

## Core Plugins and related lessons

- [Plugin State Agent](../01_basic/01_03_plugin_state_agent/README.md): one owned state field.
- [Directive Agent](../01_basic/01_04_directive_agent/README.md): validation and post-commit dispatch.
- [JSON and Scheduler](../01_basic/01_07_data_defined_agent/README.md): import a saved document with a core runtime Plugin.
- [Keyed Timers](../04_runtime/04_02_keyed_timers/README.md): Plugin-owned OTP timers.
- [Audit](../08_applications/08_01_audit/README.md): bounded records in owned Agent state.
- [SensorManager](../08_applications/08_03_inbox/README.md): manage an input source and reject duplicates.
- [Subscription](../08_applications/08_02_subscription/README.md): rebuild a live resource from committed state.
- [Plugin State Conversion](../10_persistence/10_04_plugin_state_conversion/README.md): convert persisted owned state.

## Contract summary

- `lower/2`, `normalize/1`, and `verify/2` turn custom syntax into validated, versioned data.
- `prepare/2` returns portable input; `admit/3` returns live input. Neither changes the incoming Signal or another Plugin's input.
- Actions read `context.plugin_inputs[Plugin].prepared` and `.runtime`.
- `reduce/2` reads complete candidate state and returns only its owned value.
- `after_commit/3` receives the committed value and revision before Directives run.
- Changed Plugins rebuild from `Jido.Plugin.Init`; they do not receive a hook for that configuration commit.
- `dump/3` and `load/3` convert only owned state. Startup and thaw rebuild runtime resources without replaying commit hooks.
- Direct `Agent.cmd/3` runs pure callbacks. Live admission, runtime callbacks, and commit hooks require AgentServer.
