# Plugin examples

These examples show the Plugin data and ownership contract. They start with
pure preparation, add live admission, then cover owned state and persistence.

## Learning order

1. [Prepared Input](09_01_prepared_input/README.md) — derive one portable package input without changing the Signal.
2. [Runtime Admission](09_02_runtime_admission/README.md) — derive one transient package input from private runtime state.
3. [Identity](09_03_identity/README.md) — combine pure signature verification with live replay protection.
4. [Secure Signal](09_04_secure_signal/README.md) — decrypt ciphertext into a package input and preserve the incoming Signal.
5. [Composition](09_05_composition/README.md) — use independent pure and live package inputs in one Agent.
6. [State Middleware](09_06_state_middleware/README.md) — read complete Turn state and reduce only one owned field.
7. [Persisted State](09_07_persisted_state/README.md) — convert one Plugin-owned field and reject invalid stored values.
8. [Commit Projection](09_08_commit_projection/README.md) — update a live owned-state view without Action-owned Directives.

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
- `Jido.AgentServer.Plugin.admit/3` can reject or return one transient runtime input.
- Neither preparation nor admission can change the Agent, incoming Signal, caller context, route, or another package input.
- `Jido.Agent.Plugin.reduce/2` can read the complete candidate and return only its owned state value.
- `Jido.AgentServer.Plugin.after_commit/3` receives the exact committed owned value and revision before returned Directives.
- `Jido.Persistence.Plugin.dump/3` and `load/3` convert only their paired Plugin-owned state value.
- Direct `Jido.Agent.cmd/3` runs pure preparation but not live admission or commit notification.
- Actions and Flows read `context.plugin_inputs[Package].prepared` and
  `context.plugin_inputs[Package].runtime`.
