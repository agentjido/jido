# 05 Plugins

Plugins add one complete, reusable capability to an Agent. These lessons show
the ownership boundaries one part at a time.

## Learning order

1. [Plugin-Owned State](05_01_plugin_owned_state/README.md) separates Agent
   domain state from Plugin state.
2. [Prepared Input](05_02_prepared_input/README.md) derives portable input from
   an incoming Signal.
3. [Runtime Admission](05_03_runtime_admission/README.md) derives transient
   input from private runtime state.
4. [State Reduction](05_04_state_reduction/README.md) reduces one owned field
   from the complete candidate state.
5. [Directives and Hooks](05_05_directives_and_hooks/README.md) validates a
   custom effect, observes the commit, and dispatches after it.
6. [Supervised Runtime](05_06_supervised_runtime/README.md) starts an
   activation-local resource and proves shutdown cleanup.
7. [Plugin DSL](05_07_plugin_dsl/README.md) adds validated Agent syntax.
8. [Plugin State Conversion](../12_persistence/12_04_plugin_state_conversion/README.md)
   owns the persisted representation of Plugin state.
9. [Composition](05_09_composition/README.md) combines pure and live Plugin
   input in one Agent.

Advanced examples continue with [Identity](05_10_identity/README.md),
[Secure Signal](05_11_secure_signal/README.md), and
[Authoring Extension](05_12_authoring_extension/README.md). Cryptographic
primitives remain in [shared support](support/crypto.ex).

## Run the section

```sh
mix test.examples examples/05_plugins --warnings-as-errors
```

## Core Plugins and related lessons

- [Replies and Directives](../04_agents/04_05_replies_and_directives/README.md): validation and post-commit dispatch.
- [JSON and Scheduler](../04_agents/04_08_data_defined_agent/README.md): import a saved document with a core runtime Plugin.
- [Keyed timers](../11_built_in_capabilities/11_03_keyed_timers/README.md):
  replace and cancel named timers through the built-in Scheduler capability.
- [Audit](../11_built_in_capabilities/11_01_audit/README.md): bounded records in owned Agent state.
- [SensorManager](../24_application_patterns/24_02_inbox/README.md): manage an input source and reject duplicates.
- [Subscription](../24_application_patterns/24_03_runtime_subscription/README.md): rebuild a live resource from committed state.
- [Plugin State Conversion](../12_persistence/12_04_plugin_state_conversion/README.md): convert persisted owned state.

## Contract summary

- `lower/2`, `normalize/1`, and `verify/2` turn custom syntax into validated, versioned data.
- `prepare/2` returns portable input; `admit/3` returns live input. Neither changes the incoming Signal or another Plugin's input.
- Actions read `context.plugin_inputs[Plugin].prepared` and `.runtime`.
- `reduce/2` reads complete candidate state and returns only its owned value.
- `after_commit/3` receives the committed value and revision before Directives run.
- Changed Plugins rebuild from `Jido.Plugin.Init`; they do not receive a hook for that configuration commit.
- `dump/3` and `load/3` convert only owned state. Startup and thaw rebuild runtime resources without replaying commit hooks.
- Direct `Agent.cmd/3` runs pure callbacks. Live admission, runtime callbacks, and commit hooks require AgentServer.
