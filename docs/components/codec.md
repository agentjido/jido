---
title: Jido.Codec component
status: current
last-reviewed: 2026-11-10
---

# Jido.Codec component

`Jido.Codec` is one component for schema-backed codecs, versioned documents,
portable stored values, stable references, and bounded codec diagnostics.

## Public contract

### Root document API

| Surface | Public operations |
| --- | --- |
| Install a schema-backed codec | `use Jido.Codec` and `codec/1,2` declarations |
| Encode a value | `encode/1,2`, `encode_json/1,2` |
| Decode a document | `decode/1,2`, `decode_json/1,2` |

The root router requires a string `type` and a positive integer `vsn`. It uses
an explicit codec when supplied. Otherwise, it uses the atomically published
Codec index. An explicit Catalog overrides the published Catalog. Without one, each reference lookup uses the current publication. Callbacks receive a Catalog value or `:current`; use `Jido.Codec.Reference` and `Jido.Codec.Value` to resolve it.

### Supporting public surfaces

- `Jido.Codec.Contract` defines versioned document codec metadata and callbacks.
- `Jido.Codec.Document` checks complete-document resource limits and JSON input.
- `Jido.Codec.Reference` encodes and decodes trusted Catalog references.
- `Jido.Codec.Value` encodes and decodes the closed portable-value grammar.
- `Jido.Codec.Term` checks portable BEAM terms.
- `Jido.Codec.Index` maps types, versions, and runtime value encoders to codecs.
- `Jido.Codec.Issue` is the bounded decode diagnostic value.
- `Jido.Codec.Error` is the encode and internal codec error boundary.

Compiler, Document, Contract, Index, Reference, Term, Value, Error, and Issue
are parts of one Codec component. They are not sub-components.

## Contract invariants

- Domain codecs own their document type, version, fields, and semantic checks.
- Complete-document limits run before owner-specific decoding.
- Stored atoms and other stable references resolve only through a trusted
  Catalog.
- Portable values exclude structs, tuples, processes, invalid UTF-8, improper
  lists, and unsupported map keys.
- Codec callback failures are contained and normalized.
- Decode diagnostics are ordered, bounded, and path-aware.
- Catalog lookup is inventory. It does not grant execution authority.

## Architectural boundary

### Owns

- Codec generation and the document routing workflow.
- Versioned envelope checks and callback containment.
- Complete-document resource limits.
- Portable value, reference, and term representation.
- Codec selection, encode errors, and decode issues.

### Does not own

- Domain meaning for Agent, Flow, Signal, Session, Thread, or Plugin documents.
- Definition discovery. Catalog Discovery publishes the index.
- Persistence record lifecycle or storage adapters.
- Authorization to execute decoded targets.
- Automatic upgrades between document versions.

### Dependency position

The current Codec component crosses Reach layers:

- Compiler, Document, Encoder, Error, Index, Issue, and Term are in
  `primitives`.
- Root Codec, Contract, Reference, and Value are in `value_model`.
- Domain codecs stay in their owning higher-layer components.

This current split conflicts with a rule that requires one Covenant component
to own modules from only one Reach layer.

## Covenant and evidence

Current Codec proof is split:

- `jido_action.authoring` covers Catalog references, portable values, and
  complete-document limits.
- `jido_action.codec` covers the Flow document format and trusted target
  resolution. Its module list still names older Flow codec modules.

The Codec tests under `test/jido/codec/` cover compiler, document, index,
reference, term, value, Agent, Flow, and Signal integration behavior.

## Boundary review

Codec is one architectural component in the confirmed component map. The
current Reach and Covenant models split its ownership. This is an unresolved
architecture alignment issue, not a reason to invent Codec sub-components.

## Sources

- [`Jido.Codec`](../../lib/jido/codec.ex)
- [`Jido.Codec.Contract`](../../lib/jido/codec/contract.ex)
- [`Jido.Codec.Document`](../../lib/jido/codec/document.ex)
- [`Jido.Codec.Value`](../../lib/jido/codec/value.ex)
- [Authoring Covenant obligations](../../test/contracts/jido_action/authoring.obligations.md)
- [Flow codec Covenant obligations](../../test/contracts/jido_action/codec.obligations.md)
- [Reach layers](../../.reach.exs)

