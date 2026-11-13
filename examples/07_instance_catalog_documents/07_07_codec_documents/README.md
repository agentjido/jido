# 07_07 Codec documents

Store a trusted Agent definition and its logical address as separate bounded
documents.

## What you will learn

- `Jido.Codec` routes a versioned Agent definition through a trusted Catalog.
- `Jido.Agent.Ref` has a separate exact public representation.
- Complete-document byte, duplicate-key, and nesting limits apply before use.

## Read the code

Read [the codec example](codec_documents.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_07_codec_documents --warnings-as-errors`

Expected result: the definition and Ref round trip. Oversized, duplicate-key,
and deeply nested documents fail with explicit reasons.

## Important behavior

The Catalog resolves only installed trusted targets. A stored document does
not install code or grant permission to run it.

## Limits

The codec does not upgrade old documents automatically. Application code owns
version selection and migration.

## Core Fit and Gaps

Definition codecs, Catalog references, stable Agent references, and document
limits compose through public APIs. The application must still define which
Catalog entries are allowed for each stored-document source. This is an
authorization policy, not a Codec responsibility.

Decode with an explicit Catalog still needs the global codec index or an
explicit codec module. The bundled Agent and Flow codec modules are hidden
from generated documentation. This example obtains the current writer as an
opaque value through `Jido.Codec.Encoder.codec/1`. An importer with only a
stored document has no equivalent public selector. This is `EX-013` in the
[gap register](../../core_gaps.md).

## Files

- [Source](codec_documents.ex)
- [Tests](codec_documents_test.exs)

Previous: [Portable values](../07_06_portable_values/README.md) | Next: [Application supervision](../07_08_application_supervision/README.md)
