# Plugin examples

These examples show the Plugin data and ownership contract. They start with
pure preparation, add live admission, and then compose both forms.

## Learning order

1. [Prepared Input](09_01_prepared_input/README.md) — derive one portable package input without changing the Signal.
2. [Runtime Admission](09_02_runtime_admission/README.md) — derive one transient package input from private runtime state.
3. [Identity](09_03_identity/README.md) — combine pure signature verification with live replay protection.
4. [Secure Signal](09_04_secure_signal/README.md) — decrypt ciphertext into a package input and preserve the incoming Signal.
5. [Composition](09_05_composition/README.md) — use independent pure and live package inputs in one Agent.

## Run the section

```sh
mix test test/examples/09_plugins --include example --seed 0
```

## Related use cases

- [Plugin State Agent](../01_basic/01_03_plugin_state_agent/README.md) shows one Plugin-owned Agent state field.
- [Directive Agent](../01_basic/01_04_directive_agent/README.md) shows validation and post-commit dispatch.
- [Keyed Timers](../04_runtime/04_02_keyed_timers/README.md) shows an OTP runtime owned by a Plugin.
- [Audit](../08_applications/08_01_audit/README.md) shows owned state and a runtime projection.
- [Subscription](../08_applications/08_02_subscription/README.md) rebuilds a live resource from committed Plugin state.
- [Plugin Contribution](../07_topology/07_06_plugin_contribution/README.md) shows a pure Topology facet.

## Contract summary

- `Jido.Agent.Plugin.prepare/2` can reject or return one portable input.
- `Jido.AgentServer.Plugin.admit/3` can reject or replace only its package input.
- Neither callback can change the Agent, incoming Signal, caller context, route, or another package input.
- Direct `Jido.Agent.cmd/3` runs pure preparation but not live admission.
- Actions and Flows read prepared values from `context.plugin_inputs`.
