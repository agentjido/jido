# 07_03 Stable Agent Addresses

Keep one portable address for an Agent instead of its current PID.

## What you will learn

- `Jido.agent_address/3` adds the instance namespace to an Agent identity.
- `Jido.Agent.Address.to_map/1` creates one exact versioned public document.
- Address decoding rejects unknown and invalid identity fields.

## Read the code

Read [the stable Address functions](stable_addresses.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_03_stable_addresses --warnings-as-errors`

Expected result: the Address round trip preserves its exact identity, and invalid
documents fail validation.

## Important behavior

A Address contains no PID, runtime location, Agent module, or state revision.

## Limits

A Address is an address. It is not an authorization credential.

## Files

- [Source](stable_addresses.ex)
- [Tests](stable_addresses_test.exs)

Previous: [Namespaces and partitions](../07_02_namespaces_and_partitions/README.md) | Next: [Logical identity](../07_04_logical_identity/README.md)
