# 07_06 Portable values

Reject process-local values before Agent data crosses a storage boundary.

## What you will learn

- `Jido.Codec.Term` accepts nested BEAM domain data.
- PIDs, ports, references, functions, improper lists, and partial bitstrings
  cannot enter stored values.
- Validation reports a bounded path to the first rejected value.

## Read the code

Read [the portable value boundary](portable_values.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_06_portable_values --warnings-as-errors`

Expected result: portable domain data passes, and a nested PID fails at
`[:agent_state, :runtime, :worker]`.

## Important behavior

Runtime clients, callbacks, PIDs, ports, references, and functions belong in
execution context or supervised runtime resources. They do not belong in Agent
state, Signals, Sessions, Directives, or checkpoints.

## Limits

Term portability does not mean JSON compatibility. The next lesson applies
JSON document limits.

## Files

- [Source](portable_values.ex)
- [Tests](portable_values_test.exs)

Previous: [Catalog discovery](../07_05_catalog_discovery/README.md) | Next: [Codec documents](../07_07_codec_documents/README.md)
