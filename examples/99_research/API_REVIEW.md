# Topology API Review: Issues 394 and 395

Status: implementation candidate for PR review. The first commit records the
failing examples. The later commits implement the core fix. Review these
public contracts before merge, including the DSL member selector.

## Member selection

The compiled module form stays valid:

```elixir
agent :alice, Worker, initial_state: %{total: 2}
%{key: :alice, module: Worker, initial_state: %{total: 2}}
```

The neutral definition has a separate selector:

```elixir
agent :alice, definition: stored_alice, initial_state: %{total: 2}
%{key: :alice, definition: stored_alice, initial_state: %{total: 2}}
```

Groups use the same selector. Exactly one selector is required. An Agent
instance is not a definition. Planning retains the exact definition and checks
resolved state before startup. Activation uses that selected schema, routes,
metadata, and Plugins. The existing positional module argument accepts a
compiled module only.

See the [member examples](99_03_data_defined_topology/README.md).

## Runtime and child gates

`use Jido.Topology` generates `child_spec/1`, which delegates to
`Jido.Topology.Runtime`. The Runtime owns an optional director, Controller,
members, resources, and child branches. Eager mode starts all local members.
Deferred and lazy modes start control processes only. Calls start the requested
dependency closure. Publication delivers to active Bus subscribers only.

A `children` data entry selects a DSL or neutral Topology, an optional neutral
director, input mapping, activation mode, gate, and branch restart limits.
The gate declares exact command types and member targets. Event exports need
an explicit `to` parent Bus target. Empty exports keep the Buses separate.
Child identity is scoped under the parent ID. Each child owns its director,
Controller, members, and resources. Static `include` still makes one Controller
plan and rejects runtime children. There is no new child DSL block grammar.

See the [child examples](99_04_child_topology_runtime/README.md) for status,
lookup, deadlines, lifecycle events, recovery, and shutdown contracts.

## Version and restore rules

Topology Codec version 2 remains the format for module-only definitions.
Version 3 adds neutral member definitions and child runtime definitions.
Both decode through the trusted Registry. A version 2 document cannot contain
the new fields. Stored strings cannot select new atoms or executable modules.

The authored Agent version stays in the source definition and execution plan.
The Controller derives an unversioned runtime definition because it adds
ownership metadata and Bus input Plugins. On restart it uses the current
accepted definition and restores committed state through Jido. State must pass
that definition's schema. Jido does not fetch a changed database document.
Existing members cannot change through an additive update. Such changes need
explicit replacement or the existing Agent upgrade API.

A local checkpoint survives member failure and ancestor runtime failure.
An explicit runtime stop removes local checkpoints. Jido instance loss removes
its local store; recovery then requires the configured persistence adapter.
The runtime owner PID is runtime configuration and is never a stored definition.

## Review scope

Review the `definition:` DSL selector, generated child specification, Runtime
API names, gate data form, event target, status and error fields, Bus policy,
and restore rules. Keep these examples in research until the PR contract is
accepted. Promotion to the main example catalog is a separate documentation
change after review.
