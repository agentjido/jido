# 09_03 Identity

An identity Plugin verifies signed input before routing, rejects replay at the
live boundary, and signs the correlated reply.

## What you will learn

- How pure Plugin preparation verifies a signature without changing the Signal.
- How live Plugin admission claims a nonce to reject replay.
- How outbound preparation signs a reply after correlation data is present.
- Why the transient replay set lasts for one Plugin runtime generation.
- Why admission can consume a nonce before later route execution fails.

## Read the code

Read [the Agent](identity.ex), [the identity Plugin](identity_plugin.ex), then
[the shared cryptographic helpers](../support/crypto.ex).

## Run it

```sh
mix test test/examples/09_plugins/09_03_identity --include example --seed 0
```

Expected result: one valid request commits and receives a signed reply. A
replay fails during the same runtime generation. After runtime replacement,
the same request can commit again. A signed request with invalid route data
fails after admission, and its nonce is rejected on retry. A forged request
fails without changing Agent state.

## Important behavior

Pure preparation returns the verified public key and nonce under the identity
package `prepared` slot in `context.plugin_inputs`. This path works in direct
`cmd/3`.
Live admission claims the nonce before execution. The signing private key and
replay set stay in Plugin runtime state. Replay protection therefore lasts for
one runtime generation only. A runtime restart creates a new key pair and an
empty replay set. Agent state stores only the accepted public identity.

Admission happens before route selection and execution. If later route input
validation or execution fails, the runtime has still consumed the nonce.

## Limits

The fixed deterministic keys are for local learning only. Production key
storage, rotation, durable or distributed replay protection, and nonce expiry
are not included.

## Files

- [Agent](identity.ex)
- [Plugin](identity_plugin.ex)
- [Shared cryptographic helpers](../support/crypto.ex)
- [Tests](../../../test/examples/09_plugins/09_03_identity/identity_test.exs)

Previous: [Runtime Admission](../09_02_runtime_admission/README.md) | Next: [Secure Signal](../09_04_secure_signal/README.md)
