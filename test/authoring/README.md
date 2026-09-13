# Authoring verification

This suite checks Agent and Topology definitions through source compilation,
extraction, direct data, Builders, saved JSON, and instance construction.
It has 26 saved cases: 15 Agent cases and 11 Topology cases.
Keyword and block variants give 28 source variants in total. Additional fault
fixtures check Plugin failures and invalid source without adding saved cases.

Run both sets with:

```sh
mix test.authoring
```

Run one set with:

```sh
mix test test/authoring/agents --only authoring --seed 0
mix test test/authoring/topology --only authoring --seed 0
```

`mix test.all` includes this suite. Plain `mix test` and `mix quality` exclude
the `:authoring` tag. There is no authoring CI job.

## Scope

- [Agent cases](agents/README.md) check complete state, direct execution, live
  commits, rejected inputs, and recovery.
- [Topology cases](topology/README.md) check complete pure plans, input
  validation, groups, ownership, buses, composition, and Plugin contributions.
- `support/agents/` and `support/topology/` hold each corpus's case data,
  loaders, source fixtures, and saved JSON. Only `support/compiler.exs` is
  shared. Source fixtures load in selected tests, not during test discovery
  or normal Mix compilation.

## Layout

```text
authoring/
  agents/
    authoring_test.exs
    boundaries_test.exs
    metadata_test.exs
    execution_test.exs     # Direct and live Agent execution
    README.md
  topology/
    authoring_test.exs
    boundaries_test.exs
    composition_boundaries_test.exs
    plugin_boundaries_test.exs
    metadata_test.exs
    README.md
  support/
    compiler.exs          # Shared source compiler
    agents/
      cases.exs
      corpus.exs
      fixtures/           # Valid source and its dependencies
        invalid/
        json/
    topology/
      cases.exs
      corpus.exs
      fixtures/           # Valid source and its dependencies
        invalid/
        json/
  README.md
```

The namespaces match the domains:

- `JidoTest.Authoring.Agents.{Cases, Corpus, Fixtures}`
- `JidoTest.Authoring.Topology.{Cases, Corpus, Fixtures}`
- `JidoTest.Authoring.Compiler` for the shared compiler

Each domain keeps its test modules in the same namespace. Invalid source uses
`Fixtures.Invalid`. `Cases` owns independent expectations; `Corpus` owns
fixture loading and authoring-form construction. These modules stay separate
because Agent state and execution differ from Topology inputs and plans.

Both sets have six authoring forms: module, direct map, direct keyword list,
incremental Builder, module-seeded Builder, and saved JSON. Expected declarations,
state, and plans are independent test data. Tests never rewrite JSON documents.
Additional boundary tests check invalid source, metadata, and malformed documents.

Keep focused public-contract, compiler, and generated-helper tests in
`test/jido/`. Core tests must not depend on this optional suite. Keep Topology
controller startup, recovery, and distributed lifecycle tests in the existing
runtime suites.

## Confirmed fixes

Both block DSLs rejected string metadata keys that other authoring forms
accepted. They also failed with a protocol error for a struct used as metadata.
Each DSL now uses its own core metadata validator. The Topology validator still
rejects runtime values; the Agent and Topology contracts remain separate.

## Limits

This is a fixed regression corpus, not yet a full burn-in tool. It does not
generate random input, reconstruct definitions in a fresh BEAM, run long
recompilation loops, or set performance limits. Add small cases for new
contracts before adding a general test framework.
