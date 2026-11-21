---
title: Jido.Joi component
status: current
last-reviewed: 2026-11-10
---

# Jido.Joi component

`Jido.Joi` is the Jido schema and data-lifecycle facade over Zoi 0.19.

## Public contract

Joi schemas are ordinary Zoi schemas. Jido supports a curated Zoi surface and
adds Jido policies.

The facade excludes `base64/0,1`, `base64url/0,1`, `ipv4/0,1`, `ipv6/0,1`,
and `null/0,1` because Jido does not use them.

| Surface | Public operations |
| --- | --- |
| Schema constructors | Scalar, collection, object, struct, union, intersection, enum, literal, lazy, codec, and refinement constructors |
| External input | `parse/2,3` and `parse!/2,3` |
| Stored-state creation | `initialize/2` |
| Stored-state checks | `validate/2`, `validate_stored_schema/1` |
| Static authoring checks | `validate_static/1` |
| Struct support | `enforce_keys/1`, `struct_fields/1`, `type_spec/1,2` |
| Error access | `error_code/1`, `error_path/1`, `error_message/1`, `changed_value?/1` |
| JSON Schema | `to_json_schema/1` |
| Deterministic schema data | `canonicalize/1` |

The data lifecycle has three different operations:

1. `parse/3` accepts external input and can convert it.
2. `initialize/2` can add checked defaults but cannot change supplied values.
3. `validate/2` checks stored values without adding defaults or changing data.

Map and keyword schemas are open by default. Stored Agent state uses a closed
boundary. Jido does not use the Zoi `:strip` policy because stripping changes
the data shape.

Object and struct field lists use deterministic key order, including nested
schemas and extensions. Their authored map iteration order cannot change
generated code fingerprints between clean builds. Keyword fields, union
branches, effects, and ordinary lists retain their order. `canonicalize/1`
also normalizes schemas inside enclosing data; it does not authorize a code
upgrade or change the strict checkpoint reference check.

`Jido.Joi.Schema` and `Jido.Joi.Runtime` have `@moduledoc false`. Their exports
support the root facade and are not separate component APIs.

## Architectural boundary

### Owns

- The curated Zoi API that Jido supports.
- Open and closed key policies used by Jido.
- The parse, initialize, and validate lifecycle.
- Stored-schema safety rules.
- Static authoring-data checks and schema projections.

### Does not own

- Zoi implementation behavior outside the curated facade.
- Domain schemas for Actions, Agents, Signals, Plugins, or Flows.
- Codec document routing or persistence formats.
- Authorization or runtime process policy.

### Dependency position

`.reach.exs` places `Jido.Joi` and its internal modules in `primitives`. Almost
all definition, Agent, Plugin, persistence, and AI namespaces consume Joi.

## Covenant and evidence

There is no focused active Covenant component for `Jido.Joi`. Unit tests in
`test/jido/joi_test.exs` and Agent runtime tests cover the current lifecycle.
`test/jido/joi_rebuild_test.exs` compiles the same schema-based Action in two
independent VMs with different atom creation order, restores its checkpoint,
and confirms that a real executable body change still rejects recovery.

The lack of a focused Covenant owner is a proof gap. Joi behavior also appears
inside broad legacy authoring proof, but that proof does not define a complete
Joi component boundary.

## Boundary review

Joi is one utility component. `Jido.Joi.Schema` and `Jido.Joi.Runtime` are
internal parts, not sub-components.

## Sources

- [`Jido.Joi`](../../lib/jido/joi.ex)
- [`Jido.Joi.Schema`](../../lib/jido/joi/schema.ex)
- [`Jido.Joi.Runtime`](../../lib/jido/joi/runtime.ex)
- [Joi tests](../../test/jido/joi_test.exs)
- [Reach layers](../../.reach.exs)

