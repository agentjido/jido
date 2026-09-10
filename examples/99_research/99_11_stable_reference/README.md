# 99_11 Stable Reference

Status: implemented addressing contract; awaiting a stable runtime lesson.

A `Jido.Agent.Ref` keeps durable identity while processes and local Jido
instances are replaced.

## What this proves

- One Ref resolves the current live process after persistent replacement.
- Equal Agent IDs remain isolated by their Jido namespace.

## Read the code

Read [the conversation Agent and Ref client](stable_reference.ex).

## Run it

```sh
mix test test/examples/99_research/99_11_stable_reference --include example --seed 0
```

Expected result: calls reach the correct conversation before and after process
replacement and namespace rebinding.

## Gap and limits

The public contract exists. Promote it when the runtime learning path has a
clear Ref-first addressing lesson. The controlled persistence adapter is local
and in memory.

## Files

- [Source](stable_reference.ex)
- [Tests](../../../test/examples/99_research/99_11_stable_reference/stable_reference_test.exs)

Previous: [Plugin Isolation](../99_10_plugin_isolation/README.md) | Next: [Definition Revision](../99_12_definition_revision/README.md)
