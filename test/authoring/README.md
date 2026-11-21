# Authoring equivalence tests

Run `mix test.authoring --warnings-as-errors` from the repository root.

This lane has one goal: prove that each supported authoring path produces the
same canonical Agent or Flow definition. It contains four groups:

- `agent_equivalence_test.exs` compares Agent DSL, an independent Map, and a
  fixed JSON document.
- `flow_equivalence_test.exs` compares Flow DSL, independent Maps, and JSON for
  the complete reference Flow and each public component type.
- `rejection_equivalence_test.exs` checks the same invalid definition across
  DSL, Map, and JSON boundaries.
- `authoring_safety_test.exs` checks inert authoring, Catalog requirements,
  atom safety, and the JSON size limit.

Runtime execution behavior belongs to focused tests outside this lane.
