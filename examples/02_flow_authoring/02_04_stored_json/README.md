# 02_04 Stored JSON

A trusted Catalog encodes and decodes one Flow as a portable JSON document.

## What you will learn

- How `Jido.Codec` stores a Flow through `Jido.Catalog` references.
- How an unknown Action reference returns a structured issue.

## Read the code

Read [the codec example](stored_json.ex), then [the test](stored_json_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_04_stored_json --warnings-as-errors`

Expected result: the trusted document restores the canonical `echo` Flow, and
an untrusted target is rejected.

## Important behavior

The document stores trusted references. It does not store or evaluate Elixir
source code. The example gets the current writer through the public
`Jido.Codec.Encoder` protocol and passes that opaque codec value to decode.

## Limits

Catalog trust and document transport remain application responsibilities.
Decode with only an explicit Catalog still depends on the globally published
codec index. An offline importer that has only the document has no public
selector for a bundled codec type and version. See `EX-013` in the
[gap register](../../core_gaps.md).

## Files

- [Codec example](stored_json.ex)
- [Tests](stored_json_test.exs)

[Previous: DSL Flow](../02_03_dsl_flow/README.md) |
[Next: Authoring Equivalence](../02_05_authoring_equivalence/README.md)
