# Agent authoring corpus

This suite checks the same Agent contract across authored modules, direct
attributes, Builder calls, and saved JSON. It has 15 distinct cases with 16
module variants. It is not a complete feature matrix.

Run it with:

```sh
mix test test/authoring/agents --only authoring --seed 0
```

`mix test.authoring` runs both Agent and Topology cases. `mix test.all` includes
both sets. Plain `mix test` and `mix quality` exclude
the `:authoring` tag. There is no authoring CI job.

## Current cases

| Case | Source | Main checks |
| --- | --- | --- |
| Counter | Keyword and block modules | Exact and wildcard routes, priority, defaults, optional helper |
| Inline counter | Block module with inline Action | Extracted Action target, generated helper, conversion and execution |
| Flow counter | Block module with Flow and Plugin | Flow target, Plugin configuration, complete state and owned state |
| Required profile | Keyword module | Required initial state, defaults, unknown state fields |
| False, zero, and nil | Block module | Explicit values replace route defaults; nullable input |
| Nested profile | Block module | Nested validation and preservation of other fields |
| List inputs | Block module | Required list helper, empty list, item validation |
| Bounded value | Keyword module | Lower and upper bounds, failed candidate, recovery |
| Static metadata | Block module | Date Registry reference, tuple, binary, integer versus float |
| Predicate routes | Block module | External predicate, fallback, missing route and recovery |
| Ordered routes | Block module | Equal-priority declaration order and reversed JSON |
| Built Flow | Block module | Flow value target and generated interface |
| Ordered Plugins | Block module | Owner-facet manifests, ordered reductions, reversed JSON |
| Extension route | Extension plus block module | Target lowering and the generated interface |
| Custom selection | Keyword module with callback | Behavior module identity survives conversion; recovery |
| Metadata boundaries | Three block modules | Atom, string, and mixed keys; cross-form equality and JSON round trips |
| Invalid declarations | Eight source files | Missing source, duplicate schema, optional list, helper collision, Plugin state conflict, invalid metadata |

The 16 valid module variants use six data paths: module definition, direct
map, direct keyword list, incremental Builder, module-seeded Builder, and saved
JSON. Each case/form pair has separate pure and live ExUnit tests. Shared tests
check neutral definitions, instantiation, explicit state overrides, JSON
stability, and direct versus live Turns. Specific interface tests stay explicit.
Failure steps check the error type and unchanged live snapshot. Later valid
steps prove recovery. Success steps check complete state and commit counts.

## Layout and loading

Agent support lives in `../support/agents/`, under the
`JidoTest.Authoring.Agents` namespace:

- `fixtures/*.exs` contains valid source and its Action, Flow, and Plugin dependencies.
- `fixtures/invalid/` contains source that must fail compilation.
- `fixtures/json/` contains reviewed version-2 Agent documents.
- `corpus.exs` lists source variants, loads fixtures, and constructs one
  authoring form at a time.
- `cases.exs` holds plain maps with independent expected declarations,
  initial state, overrides, invalid state, state sequences, and Registry entries.

Test files stay in this folder:

- `authoring_test.exs` runs pure definition, JSON, and instance checks.
- `execution_test.exs` uses `JidoTest.Case` for direct and live comparisons.
- `boundaries_test.exs` checks invalid source, interfaces, ordering, malformed
  JSON references, and state validation.
- `metadata_test.exs` checks metadata parity, JSON round trips, and rejected metadata.

Test discovery loads only the support modules. Each selected case requires its
source after shared dependencies. Successful loads are reused. There is no
suite-wide compilation setup that can invalidate unrelated cases.

The shared compiler in `../support/compiler.exs` runs in a monitored process so
late `after_verify` errors become
normal test assertions with the original exception and stack. This is not a
separate BEAM. Positive source must have no diagnostics. Invalid source compiles
only in its own test. No source fixture is on a normal Mix compilation path.
Pure tests do not start a Jido runtime.

## Add a case

1. Add a small source fixture and its module/file entry to the Corpus variant list.
2. Add a `Cases.spec/2` clause returning a plain map. Supply its own schema,
   instance inputs and expected states; no counter fields or helper names are
   required by the shared tests.
3. Add its JSON document and stable Registry identifiers.
4. Run `mix test.authoring` and review any JSON change.

Do not derive expected declarations or final state from the code under test.
Do not rewrite JSON snapshots during a test run. Compare decoded JSON objects;
object key order is not a contract, but route and Plugin order is.

The two counter modules share one JSON document. Each case explicitly binds
`agents/counter` to its own module in a separate trusted Registry. Other data
forms keep that module identity; tests do not remove it to force equality.
The inline Action also gets a stable Registry identifier. JSON references the
compiled code and schema; it does not contain their implementation or recreate
DSL helper declarations.

## Metadata regression

The suite found that block metadata rejected string keys accepted by the direct
constructor, Builder, and Codec. The block DSL now uses the core metadata
validator. Three focused source fixtures check atom, string, and mixed keys
across these forms. Mixed metadata retains both `:case` and `"case"` after JSON
conversion. Structs and non-map values remain invalid. Invalid block metadata
raises a DSL error, not a protocol error.

These boundary fixtures supplement the 16 full corpus variants; they do not add
live execution cases or saved JSON documents.

## Deferred work

State defaults currently treat explicit nil as missing. A focused test records
this separately from nullable Signal input, where nil remains an explicit value.

This suite does not add the full 60-case library, generated
inputs, fresh-BEAM reconstruction, recompilation loops, or performance limits.
Compilation uses the test VM. Each normal command starts a new VM, but the
suite does not yet prove transport to an independently loaded VM.
