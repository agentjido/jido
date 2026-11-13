# 07_03 Stable Agent references

Keep one portable address for an Agent instead of its current PID.

## What you will learn

- `Jido.agent_ref/3` adds the instance namespace to an Agent identity.
- `Jido.Agent.Ref.to_map/1` creates one exact versioned public document.
- Ref decoding rejects unknown and invalid identity fields.

## Read the code

Read [the stable reference functions](stable_references.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_03_stable_references --warnings-as-errors`

Expected result: the Ref round trip preserves its exact identity, and invalid
documents fail validation.

## Important behavior

A Ref contains no PID, runtime location, Agent module, or state revision.

## Limits

A Ref is an address. It is not an authorization credential.

## Files

- [Source](stable_references.ex)
- [Tests](stable_references_test.exs)

Previous: [Namespaces and partitions](../07_02_namespaces_and_partitions/README.md) | Next: [Logical identity](../07_04_logical_identity/README.md)
