# Topology API Review: Issues 394 and 395

Status: proposal only. No core or DSL changes have been made.

## Member selection

Keep the current compiled module form:

```elixir
agent :alice, Worker, initial_state: %{total: 2}
%{key: :alice, module: Worker, initial_state: %{total: 2}}
```

Add a separate neutral definition form:

```elixir
agent :alice, definition: stored_alice, initial_state: %{total: 2}
%{key: :alice, definition: stored_alice, initial_state: %{total: 2}}
```

Use the same choice for groups. Exactly one of `module` and `definition` is
required. Retain the selected neutral definition in the plan and use it during
activation. Validate the definition and resolved initial state before startup.
Use Agent Codec rules and the trusted Registry for Topology JSON transport.

The [member examples](99_03_data_defined_topology/README.md) currently pass
neutral values through `module` to expose the old restriction. If this proposal
is approved, update their common builder and direct DSL fixture to use
`definition`. The current positional DSL probe does not approve overloading
the module argument.

## Runtime and child gates

Generate `child_spec/1` from `use Jido.Topology`. Delegate to
`Jido.Topology.Runtime`, which starts and owns the director, Controller,
members, and resources. Support eager, deferred, and lazy activation.

Add a separate `children` data field for runtime nesting. A child entry selects
a DSL or neutral Topology, an optional neutral director, one gate, an activation
mode, and branch restart limits. The gate declares accepted commands and
exported events. It starts the child on demand and uses parent-scoped identity.

The [child examples](99_04_child_topology_runtime/README.md) specify lookup,
call, readiness, publication, lifecycle, recovery, and completion APIs. Those
names and policies require review. Static `include` keeps its current meaning.
Start with child data declarations; propose new child DSL grammar separately.

## Decisions that remain open

- Approve the separate `definition` field and its DSL form, or select a different form.
- Approve the generated Topology child specification and Runtime ownership.
- Review the child gate data form, status and error fields, event bridge,
  active-subscriber Bus policy, and per-child restart limits.
- Define version and restore behavior before the core fix is complete.
  Current examples restore the same supplied source; they do not select a
  policy for a changed stored definition.

The user's instruction requires review and approval before any DSL change.
These files make that proposed change available for review.
