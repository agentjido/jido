# ADR 0007: Deterministic schema field order

- Status: Accepted
- Date: 2026-11-14

## Context

Zoi converts object field maps to lists. Map iteration can differ between
BEAM instances with different atom creation order. Identical Jido source can
then embed different schema lists in its compiled modules. The strict snapshot
code-reference fingerprint correctly detects different bytes, but this blocks
recovery after an otherwise unchanged clean build.

## Decision

Joi sorts object and struct schema fields by key when it constructs or extends
a schema. It applies this rule recursively to nested schemas. Keyword fields,
union branches, effects, and ordinary data lists retain their authored order.
`Jido.Joi.canonicalize/1` applies the same rule to schemas inside enclosing data.

Keep the existing snapshot code-reference check. A genuine code change must
still reject an old checkpoint. Do not infer compatibility from a legacy MD5,
ignore a mismatch, or rewrite snapshot reference bytes automatically.

Previously written checkpoints need one explicit offline transition. First
load them under their matching old artifact, which verifies the old references.
Then compare the definitions under canonical schema field order, preserve the
validated state and settled Turn metadata, and save under the corrected code
with a revision compare-and-swap. Reject active Turns, unknown definitions,
identity changes, and stale revisions. Keep a complete data backup. This is
not permission to apply a general code upgrade without an explicit conversion.

## Evidence

Independent peer builds with opposite atom creation order produce the same
schemas and Action fingerprint, and restore the same checkpoint. A changed
Action body still fails with `changed_reference`. Persistence regression tests
check settled metadata retention and stale-write rejection.
