---
title: Jido.Expr component
status: current
last-reviewed: 2026-11-10
---

# Jido.Expr component

`Jido.Expr` provides small, data-only expressions for Flow DSL fields and other
bounded host DSLs.

## Public contract

| Surface | Public operations |
| --- | --- |
| Source authoring | `expr/1`, `parse/1,2`, `parse!/1,2` |
| Data construction | `new/2`, `new!/2`, `operations/0` |
| Host traversal | `normalize/1,2`, `reduce/3,4`, `validate/1,2` |
| Execution | `evaluate/1,2` |

The grammar is closed. It supports the documented comparison, Boolean,
arithmetic, membership, selection, and binary concatenation operations. It does
not run arbitrary Elixir code or accept new operators from a host.

Hosts can supply leaf parsers, validators, normalizers, reducers, and
resolvers. Host callbacks can handle leaf data. They cannot add operators.

Expression work is bounded by depth, node count, binary-byte count, and integer
size. Errors use `Jido.Expr.Error` with a safe path and metadata. Error details
do not include runtime operand values.

## Architectural boundary

### Owns

- The inert `Jido.Expr.Operation` data model.
- The closed source grammar and operator set.
- Bounded traversal, validation, normalization, reduction, and evaluation.
- Exact error paths and resource limits.

### Does not own

- Flow references or any other host reference type.
- A general-purpose expression language.
- Arbitrary callbacks, remote calls, assignment, or executable stored code.
- Flow execution or value resolution outside expression leaves.

### Dependency position

`.reach.exs` places all `Jido.Expr` modules in `primitives`. Flow definitions,
Flow codecs, and Exec value resolution consume the component.

## Covenant and evidence

The active Covenant component is still named `jido_action.expression`. Its four
active obligations cover operator meaning, the closed grammar, host traversal,
and resource limits.

Primary evidence:

- `test/jido/expr_test.exs`
- `test/jido/expr/elixir_conformance_test.exs`
- `test/jido/expr/survivor_contract_test.exs`
- `test/property/jido_expr/expression_contract_test.exs`

## Boundary review

The source and Reach boundary are coherent. The Covenant ID is a legacy package
name and does not match the consolidated namespace.

## Sources

- [`Jido.Expr`](../../lib/jido/expr.ex)
- [`Jido.Expr.Error`](../../lib/jido/expr/error.ex)
- [Expression Covenant obligations](../../test/contracts/jido_action/expression.obligations.md)
- [Reach layers](../../.reach.exs)

