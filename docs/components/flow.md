---
title: Jido.Flow component
status: current
last-reviewed: 2026-11-10
---

# Jido.Flow component

Purpose: Record the full Flow contract, its consumers, and its design review.
Review result: All four review checks are complete (R7). The user then approved
the Flow fixes. F1 through F5 are applied locally; see the R8 checks below.

## Source state and boundary

Reviewed HEAD `8525ec43f71656d8c9c9e5a428388aa87d159ac8` on
`migration/consolidated-v3`, on 2026-11-10. The only initial local change was
the existing `components.md` update. R7 changed documentation only.
One read-only reviewer traced module and inline authoring. The primary
reviewer traced values, graph validation, preparation, defaults, identity,
codecs, and execution seams, and reproduced the retained defects.

Flow is one component. Graph, Component, Definition, Ref, Value, Defaults,
Validation, Preparation, Identity, DSL, inline authoring, and domain codecs
are internal parts or proof surfaces. All belong to Reach `definitions`.
Flow owns a canonical control program and its authoring forms. It owns no
processes, live waits, tasks, recovery loop, Agent commit, or effect dispatch.

Instruction owns invocation values and shared configuration/compiler support.
Joi and Expr own their schema and operation engines. Catalog owns passive
registration. Codec owns document routing and general limits. Flow owns the
meaning of its stored fields after lookup. Exec owns target callbacks, Runic
compilation, execution, effects, and process cleanup. Agent owns state commit.
The review traces these seams without completing those component reviews.

## Public contract

| Surface | Supported contract |
| --- | --- |
| Data authoring | `new/1`, `new!/1` accept a plain atom-keyed definition map with `name`, optional description and schemas, a component list, and explicit non-nil `output`. They produce a canonical Flow or a structured error. Unknown keys fail. |
| Canonical value | The struct stores name, description, input/output schemas, a named component map, and output. Calls contain only kind, target, and params. Runtime context is supplied at execution. |
| Module authoring | `use Jido.Flow`, a `flow` block, and the final `output` declaration. Normal Action metadata/schema options plus `extensions:` are supported. Generated modules expose `flow/0`, `compiled/0`, `run/2`, `step_action/1`, metadata, validators, and the authoring contract. `compiled/0` and `run/2` delegate to Exec. |
| Components | Step and Subflow lower to `:call`; Timer, Await, and Selection lower to `:wait`. Choice, Map, Parallel, Reduce, Iterate, Invoke, and Handoff keep their canonical kinds. Each has closed fields, required values, and reference scopes. Choice has a fallback. Handoff is the sole terminal and its complete result is the output. |
| Values and references | Portable scalars, maps and proper lists, `Jido.Flow.Ref`, and `Jido.Expr.Operation`. Ref constructors cover input/context/result, collection items, accumulator, and iteration data; `select/2` appends a checked path. Value data/object checks reject runtime handles, unsupported structs, and invalid keys. |
| Validation and inspection | `validate/1` checks the exact canonical structure. `dependencies/1`, `explain/1`, and `semantic_identity/1` validate first and return tuples. `to_map/1` expects an artifact and preserves reference/operation/schema values. It returns deterministic component order. These calls do not run Action work. |
| Action conversion | `from_action/1`, `from_action!/1` make a one-step Flow for Agent convenience syntax. They validate that the target is an Action. |
| Partial defaults | `normalize_defaults/2`, `encode_defaults/2`, `decode_defaults/2` validate supplied fields against a Flow module's object input schema. They do not require omitted fields or add their defaults. JSON defaults use schema-based atom restoration without Catalog references. |
| Inline host API | `use Jido.Flow.Inline`, `setup!/1`, `compile!/4`, `target!/2`. This compiles an ordinary Flow module, including extensions and inline Actions. It is not a fourth data form. Its body has generated-module scope. |
| Stored documents | Public storage goes through `Jido.Codec`. The Flow domain codec writes/reads `type: "jido.flow"`, `vsn: 2`, versioned Catalog references, and tagged values. Version 1 requires explicit migration. Domain `diagnose/2` retains ordered phase errors and JSON paths. |

Structural validation is inert and accepts syntactically valid module targets
without loading their executable callbacks. Preparation checks those contracts
at compile/execution boundaries. It checks nested Flow recursion and caches
each child module's definition within that operation. Generated inline names
and semantic graph identity do not identify deployed Action code.

## Coverage and usage

Each row includes a success trace and a reachable failure trace. All rows are
traced; there is no blocked source area. The test limits below remain explicit.

| Responsibility | Source and consumer evidence | Result |
| --- | --- | --- |
| Facade and canonical data | `flow.ex`, Definition, Component; canonical/map/data-shape and unknown-key tests | Supported authoring records become exact calls/waits. Wrong fields, absent values, and malformed canonical values fail. |
| Graph and component rules | Graph, Validation; graph/dependency/accumulation/condition tests; all component kinds in authoring equivalence | References plus `needs` define the acyclic dependency graph. Duplicate names, unknown refs, bad scopes, cycles, and invalid Handoff placement fail in a defined order. |
| Values and expression integration | Ref, Value, DSL ValueParser; expression preparation, Ref path, expression boundary, and inertness tests | Nested literals/refs/operations keep distinct meaning. Limits, bad UTF-8, runtime values, improper lists, and invalid paths are rejected. F1/F2 identify literal parser gaps. |
| DSL and extensions | All DSL schemas/entities/macros, Authoring, Lowerer, InlineStep, SourceMap, ModuleCompiler, Extension; DSL/extension/compile-order tests | Schema-derived field docs, source locations, inline Action scope, extension expansion, and errors are traced. F4 identifies one source-map gap. |
| Inline Flow hosts | Inline facade/compiler/owner; Agent route inline Flows, AI inline reasoning, consumer host; inline and build tests | Typed identity, inert lookup, ownership marker, late hooks, replacement preflight, failed-body behavior, and release artifacts are traced. |
| Preparation and execution seam | Preparation and target Validation; Exec Compiler/Runtime, Agent Turn, AI tool-round Flow builder | Root and nested definitions prepare without Action work. Missing callbacks, wrong kinds, recursive nested modules, and invalid custom `flow/0` results fail. Children are materialized once per operation. |
| Defaults | Defaults; AI Agent Plugin normalization and authoring codecs; defaults tests | Partial schema fields, nested enums, atom restoration, JSON collisions, and non-portable values are traced. F3 covers an error path before normal validation. |
| Identity and inspection | Identity, Definition mapping, Graph, Flow protocol; Exec component IDs and Invoke identity; graph identity/inspection tests | Canonical graph identity is deterministic in the checked runtime. Descriptions, component metadata, and source order do not change it. Literal maps stay distinct from references. F5 removes a redundant traversal. |
| Domain codec | Codec, Reader, Writer, Value, Paths, Limits; public Codec router and Catalog references; Flow codec and authoring tests | Version 2 round trips preserve meaning and identity. Bad tags, unknown keys, duplicate decoded keys, missing registrations, wrong schemas, unavailable modules, and limits fail without partial Flows. |

The review read the Flow guides for authoring, data, inspection, identity,
storage, inline hosts, and extensions. It checked the fixed authoring JSON
fixture, external consumer builds, Exec/Agent tests, and the Flow, inline Flow,
authoring, and domain codec obligations. Supporting repositories were not
changed or used as current implementation owners.

## Findings

The evidence in this section describes the R7 source state. The later R8
changes address these findings without changing component ownership.

### F1 — Resolve literal module aliases in the declaration scope

- **Class:** Defect. **Priority:** P2. **Confidence:** High.
- **Evidence:** `lib/jido/flow/dsl/value_parser.ex:173` uses
  `Module.concat(parts)` for quoted aliases. The parser receives no caller
  environment. With `alias String, as: Text`, a Step parameter
  `%{module: value(Text)}` compiles to `%{module: Text}` (`Elixir.Text`), not
  `%{module: String}`. A temporary compiled Flow reproduced this and emitted
  an unused-alias warning. The expression test explicitly supports module
  literals through `value(Jido.Flow)`.
- **Consumer impact:** Valid Elixir alias syntax silently changes literal data
  given to an Action. DSL and independently authored map data disagree.
- **Smallest recommendation:** Resolve only permitted literal aliases in the
  declaration environment before the quoted fields lose that environment.
  Keep the closed data grammar. Do not evaluate arbitrary expression calls.
- **Compatibility:** Fully qualified module literals can stay unchanged.
  Aliased literals will receive their intended module, which changes data
  produced by this faulty path. No stored format change is needed.
- **Verification after a change:** Compare aliased, fully qualified, nested
  map/list, and map-authored literals. Include an extension and an inline
  Step binding. Keep executable-expression rejection tests.

### F2 — Check literal map duplicates after key conversion

- **Class:** Defect. **Priority:** P3. **Confidence:** High.
- **Evidence:** `lib/jido/flow/dsl/value_parser.ex:179` checks raw AST keys,
  then converts keys inside `Map.new/2`. The temporary parser probe
  `value(%{String => 1, Elixir.String => 2})` returned
  `{:ok, %{String => 2}}`. Repeating `String` on two source lines did the
  same, because the AST metadata differs. A plain duplicate atom key was
  rejected. Current parser source and expression tests require duplicate
  Flow map keys to fail.
- **Consumer impact:** A literal can discard an entry without a diagnostic.
  The two spellings can denote the same canonical key.
- **Smallest recommendation:** Convert each key once, then check membership
  while building the map. Remove the raw AST uniqueness pass. Keep values
  literal and preserve the existing error boundary.
- **Compatibility:** Valid maps do not change. Previously accepted duplicate
  literals will fail compilation. No general map or codec policy must change.
- **Verification after a change:** Check duplicate module keys with different
  spellings and lines, duplicate atom keys, and distinct module keys. Check
  a complete Flow declaration as well as the parser.

### F3 — Reject improper defaults before restoring array atoms

- **Class:** Defect. **Priority:** P3. **Confidence:** High.
- **Evidence:** `lib/jido/flow/defaults.ex:32` restores data before its final
  normalization. `restore_array_atoms/2` at `:165` calls `Enum.map/2` on any
  list. With a list-of-enum field, `decode_defaults/2` on
  `%{modes: ["safe" | :tail]}` raised `FunctionClauseError`. The same probe
  failed inside a nested object. The public spec permits an error tuple for
  invalid term input; it does not advertise this exception.
- **Consumer impact:** A direct Elixir caller can leave the public error
  contract before validation. The AI Plugin also calls this API, but normal
  JSON decoding cannot produce an improper list. No valid JSON failure is
  claimed.
- **Smallest recommendation:** Leave an improper array value unchanged for
  the existing schema/error path, or reject it locally with its field path.
  Do not add a general exception wrapper or a second defaults engine.
- **Compatibility:** Invalid input returns a structured error instead of
  raising. Valid defaults and normal JSON stay unchanged.
- **Verification after a change:** Check direct and nested improper arrays,
  an array in a union, valid enum arrays, and the existing round-trip cases.

### F4 — Retain source locations for Selection children

- **Class:** Defect. **Priority:** P3. **Confidence:** High.
- **Evidence:** `lib/jido/flow/dsl/source_map.ex:86` records Choice options
  only when the entity also has `fallback`. Selection has options but no
  fallback. No Selection child path is stored. A compiled Flow with Selection
  on line 4 and `await "", event: "ready"` on line 5 reported the compile
  error on line 4. A valid Selection's source map also had no option entries.
- **Consumer impact:** Nested wait diagnostics point to the parent instead
  of the declaration that failed. Valid graph execution is unaffected.
- **Smallest recommendation:** Record option sources for Selection as well
  as Choice. Keep fallback handling conditional. Extend the existing local
  source-map path; do not add another source-map layer.
- **Compatibility:** Diagnostic lines improve. Canonical Flow data and
  semantic identity stay unchanged.
- **Verification after a change:** Assert Timer and Await child locations by
  index and name in a Selection. Check invalid child names/fields and the
  existing Choice, Parallel, and Iterate location cases.

### F5 — Remove the identity traversal used for inspection

- **Class:** Safe refinement. **Priority:** P3. **Confidence:** High.
- **Evidence:** `lib/jido/flow/value.ex:111` recursively rebuilds maps, lists,
  and operation operands while retaining every canonical value. Ref and
  schema structs are returned unchanged. The only production entry callers
  are Definition mapping and Flow `to_map/1`/`explain/1`. Source inspection
  establishes the identity transformation. A temporary probe confirmed exact
  equality for scalar, nested Ref, operation, and Joi schema values.
- **Consumer impact:** Inspection keeps an unnecessary traversal and implies
  that values need conversion. No measured speed claim is made.
- **Smallest recommendation:** Pass canonical values directly. Remove the
  internal `Value.to_map/1` traversal and its calls. Keep public Flow
  `to_map/1`, component ordering, and the addition of each component's name.
- **Compatibility:** Supported inspection results stay exactly equal,
  including struct tags. This is not a proposal to replace public inspection
  APIs or use their maps as stored JSON.
- **Verification after a change:** Use current canonical-data, graph identity,
  inspection, and authoring equivalence tests. Compare exact output terms.

## Decisions and behavior to preserve

| Decision | Evidence and reason | Reopen condition |
| --- | --- | --- |
| Preserve one canonical Flow | DSL, map, and fixed JSON authoring tests give each form a use. Inline Flow emits a normal module. None needs a new runtime type. | A new authoring form cannot lower to this value. |
| Preserve small call records | Context and metadata belong to invocation/runtime owners. Replacing each call with an Instruction would add fields and lifecycle rules to portable graph data. | A verified graph contract needs those fields. |
| Preserve structural validation and preparation as separate phases | Inertness tests and untrusted stored data require no Action callback work during structural checks. Exec needs target and recursion checks before execution. | The trust boundary changes explicitly. |
| Preserve graph, identity, and source-map roles | Graph orders data; identity excludes display metadata; source maps retain declaration locations outside canonical values. Their outputs have distinct consumers. | A consumer contract can be removed. |
| Preserve Defaults separate from tagged Flow storage | AI Plugin defaults are partial schema data without Catalog references. Full Flow storage resolves registered atoms, schemas, and targets. One common encoder would need policy switches. | A concrete shared contract reduces total code and caller rules. |
| Preserve domain codec ownership | Reader/Writer use Component field metadata; Codec and Catalog supply lower-layer limits/references. Moving domain cases to base Codec would reverse that ownership. | A general representation need appears outside Flow. |
| Preserve Action and Flow inline scope differences | Action needs owner private helpers. Embedded Flow uses a fresh generated module and its own DSL state. A common host framework is not justified. | Both public scope and replacement guarantees become the same. |

No supported public Flow API was proved removable. F5 removes an internal
traversal. Public inspection, partial defaults, inline hosts, extensions, and stored
data all have callers or documented compatibility. Their removal needs a
product decision and a migration rule, not only a search with no internal
caller. No new shared abstraction is recommended.

## R8 — Local Flow repairs

- **F1:** Authoring resolves module aliases before Spark stores quoted values.
  Field-block expansion uses each field's environment, so aliases declared
  inside the block keep their meaning. Keyword fields, Step and Parallel
  inline bindings, Iterate state/body/update fields, extension declarations,
  and output have regression checks. Extension fields without line metadata
  use the declaration line. Only alias nodes are expanded; arbitrary calls
  remain subject to the existing closed parser.
- **F2:** The literal parser converts each map key once and checks it against
  the keys already stored. Different module spellings, different source
  lines, aliases, and nested maps cannot silently replace an earlier entry.
- **F3:** Atom restoration leaves an improper array unchanged for schema
  validation. Direct, nested, and union cases return structured errors. The
  nested case uses the enclosing schema field path (`[:nested]`). Valid enum
  arrays still restore their atoms. Union branch checks reuse the existing
  parse error boundary, including a proper outer array with an improper
  inner array. No general exception wrapper was added.
- **F4:** SourceMap records options for both Choice and Selection. Await and
  Timer locations are checked by name and index. Invalid child declarations
  report the child line.
- **F5:** Inspection uses canonical values directly. The internal
  `Value.to_map/1` traversal is removed. Public `Flow.to_map/1`, component
  ordering, reference tags, operations, and Joi schemas are preserved.

Flow obligations I7 and I8 now state the literal and Selection rules. I12
records the partial-default error boundary. Defaults is listed under its
existing Flow owner. Covenant regenerated `test/contracts/coverage.json`.
The Action source and sibling repositories were not changed by this work.

The full offline test command completed all stages before the final extension
line-metadata and nested-union guards. It passed 3,397 default tests, 8 authoring
tests, all 325 active Covenant obligations, 261 examples, the property and fuzz suites, load
tests, peer tests, and benchmark-runner tests. One property and one fuzz test
were skipped. After the extension guard, the focused Action/Flow command passed
**593 tests**, and `mix test.authoring --warnings-as-errors` passed **8 tests**.
The final nested-union regression first reproduced a restoration exception,
then passed with the repair. All **24 tests** in the four regression files
passed on that final source.

`mix quality` passed compilation, formatting, and its Credo stages. It stopped
at six unused Dialyzer filters: five for unchanged `action.ex` and one for
unchanged `catalog/discovery.ex`. A separate test-environment Dialyzer run
reported three Action callback type mismatches and one unreachable Catalog
pattern. The Action return terms and lines match the deliberate failure
fixtures (`UnsupportedResult`, `ErrorWithExtrasAction`, and `KillingAction`).
No Flow file was reported. These baseline/filter reports are not fixed by
this work; the static quality gate does not pass. The separate ExDNA check
passed at the existing 17-clone limit. Reach passed its architecture policy
and printed 281 advisory findings.

The later full Covenant command hit one durable-turn recovery timeout in
`runtime_test.exs:195`. That test then passed alone (1 test, 22 excluded).
The earlier full offline command passed it. A full retry then passed 3,397
tests and all 325 obligations. The cause is not established; shared-worktree
Exec edits are outside these Flow repairs. The final Covenant check after
the nested-union guard passed **3,397 tests** and **325/325 obligations**.
Compilation with warnings as errors passed on the final source. Final format,
patch, and all 77 local file/section links passed. Live providers, external services, and other
Elixir/OTP versions remain untested. No commit or push was made.

## R7 checks and proof gaps

The focused command passed **587 tests**, seed `0`:

```sh
mix test test/jido/action test/jido/flow test/jido/codec/flow_test.exs \
  test/jido/exec/validation_contract_test.exs \
  test/jido/exec/flow_execution_test.exs \
  test/jido/exec/action_effect_count_test.exs \
  test/jido/agent/flow_effects_test.exs \
  test/jido/agent/flow_modes_test.exs --seed 0
```

- `mix test.authoring --warnings-as-errors` passed **8 tests**, as a separate
  command total. It compares independent DSL, map, and fixed JSON definitions
  and rejection/safety cases.
- `MIX_ENV=test mix compile --warnings-as-errors` passed.
- `mix format --check-formatted` passed. All 75 local document links resolve.
  Checklist counts and `git diff --check` passed. A separate read-only
  verifier checked both records against source, callers, tests, obligations,
  and the temporary probe script. It found no material record error. It did
  not rerun the test commands; those results are coordinated evidence.
- Temporary probes reproduced F1 through F4 and supported F5. Boolean, nil,
  and normal atom enum defaults round trips passed; no enum defect is claimed.
  The probe script was outside the repository under `/private/tmp`.
- The first focused command failed on Mix's sandbox local TCP lock
  (`:eperm`). The retry with local TCP access passed. No source repair was
  required to run the tests. Isolated consumer builds passed in this run.
- No full CI, full quality gate, full Covenant command, benchmark, live
  provider call, or other Elixir/OTP version was run. Passing focused tests
  do not verify these findings as fixed or establish release readiness.
- Covenant module metadata needed alignment at R7. R8 adds Defaults. The Flow
  list still omits Preparation, Parallel entities/macros, and
  Timer/Await/Selection support.
  Flow domain codec proof stays under `jido_action.codec`; inline Flow has
  its own proof ID. These are proof gaps inside one Flow component. They do
  not create sub-components. Test tags prove named facets, not every branch.
- External public consumers were not surveyed. The local isolated consumer,
  current guides, tests, and production source bound the compatibility claims.

The R7 review did not authorize repairs. The user's later request authorized
the R8 Flow changes. R7 evidence and limits remain above as review history.

## Sources

- [Flow](../../lib/jido/flow.ex)
- [Definition](../../lib/jido/flow/definition.ex)
- [Component](../../lib/jido/flow/component.ex)
- [Graph](../../lib/jido/flow/graph.ex)
- [Ref](../../lib/jido/flow/ref.ex)
- [Value](../../lib/jido/flow/value.ex)
- [Validation](../../lib/jido/flow/validation.ex)
- [Preparation](../../lib/jido/flow/preparation.ex)
- [Defaults](../../lib/jido/flow/defaults.ex)
- [Identity](../../lib/jido/flow/identity.ex)
- [DSL support](../../lib/jido/flow/dsl)
- [Inline Flow](../../lib/jido/flow/inline.ex)
- [Domain codec](../../lib/jido/flow/codec.ex)
- [Flow tests](../../test/jido/flow)
- [Codec tests](../../test/jido/codec/flow_test.exs)
- [Authoring tests](../../test/authoring/README.md)
- [Flow obligations](../../test/contracts/jido_action/flow.obligations.md)
- [Inline Flow obligations](../../test/contracts/jido_action/inline_flow.obligations.md)
- [Domain codec obligations](../../test/contracts/jido_action/codec.obligations.md)
