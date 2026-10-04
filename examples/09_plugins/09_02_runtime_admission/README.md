# 09_02 Runtime Admission

An Agent Server Plugin uses private runtime state to add one transient
authorization input.

## What you will learn

- Why private runtime work belongs in `admit/3`, not pure `prepare/2`.
- How readiness completes before admission reads private runtime state.
- How validation rejects malformed runtime configuration before startup.
- How portable prepared input stays separate from transient runtime input.
- Why a live package input can contain a PID, reference, or function.
- Why direct `cmd/3` cannot use this live-only capability.

## Run it

```sh
mix test test/examples/09_plugins/09_02_runtime_admission --include example --seed 0
```

The authorization contains a transient lease reference. The Action consumes
`context.plugin_inputs[Package].runtime` but does not copy the reference into
Agent state. Pure preparation reports only whether a token exists. It does not
copy the token or the runtime authorization. Direct `cmd/3` gets the prepared
value but fails because live admission did not supply runtime input.

The Plugin validates a nonempty, unique token table before its child starts.
Its `await_ready/2` callback completes only after the runtime can authorize a
request. `AgentServer.await_ready/2` exposes that boundary to callers.

Previous: [Prepared Input](../09_01_prepared_input/README.md) | Next: [Identity](../09_03_identity/README.md)
