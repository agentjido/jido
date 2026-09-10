# 09_04 Secure Signal

Two Plugins verify encrypted input before decryption and encrypt a reply before
it is signed.

## What you will learn

- How Plugin order protects secure Signal admission and dispatch.
- How decrypted data stays in a temporary package-owned input.

## Read the code

Read [the Agent](secure_signal.ex), [the secure Plugin](secure_signal_plugin.ex),
then [the identity Plugin](../09_03_identity/identity_plugin.ex).

## Run it

```sh
mix test test/examples/09_plugins/09_04_secure_signal --include example --seed 0
```

Expected result: the Agent accepts a signed encrypted request and returns a
signed encrypted reply without committing plaintext secure data.

## Important behavior

Identity verification runs before secure admission. Secure admission writes
plaintext only to `context.plugin_inputs[SecureSignal.Plugin].runtime`. The
signed ciphertext Signal stays unchanged. On dispatch, encryption runs before
identity signing.

Decryption needs a live runtime because the key is private runtime state.
Therefore, direct `Jido.Agent.cmd/3` does not decrypt this Signal.

## Limits

The symmetric key is a deterministic local fixture. This example does not show
key exchange, rotation, or secure hardware storage.

## Files

- [Agent](secure_signal.ex)
- [Secure Plugin](secure_signal_plugin.ex)
- [Identity Plugin](../09_03_identity/identity_plugin.ex)
- [Shared cryptographic helpers](../support/crypto.ex)
- [Tests](../../../test/examples/09_plugins/09_04_secure_signal/secure_signal_test.exs)

Previous: [Identity](../09_03_identity/README.md) | Next: [Composition](../09_05_composition/README.md)
