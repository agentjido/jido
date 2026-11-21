---
title: Jido.Action component
status: current
last-reviewed: 2026-11-10
---

# Jido.Action component

Purpose: Record the Action contract, its consumers, and its design review.
Review result: All four review checks are complete (R7). One safe refinement
remains open. No Action defect was confirmed. No recommendation is approved
for implementation.

## Source state and boundary

Reviewed HEAD `8525ec43f71656d8c9c9e5a428388aa87d159ac8` on
`migration/consolidated-v3`, on 2026-11-10. The only initial local change was
the existing `components.md` update. The R7 review changed documentation only.
One read-only reviewer traced Action. The primary reviewer checked the
integration paths, the retained finding, and the focused test results.

Action is one component. Its inline compiler, parser, owner hooks, validation,
Output envelope, and effect requests are internal parts or proof surfaces.
All Action source belongs to Reach `definitions`. Action owns a unit of work;
it does not own Flow structure, execution policy, Agent state commit, or effect
dispatch. It needs no process or supervisor of its own.

Instruction owns invocation values and the shared Compiler and Config.
Joi owns schema parsing. Exec owns callback containment, retry, timeout,
continuation, handoff, and cleanup. Agent owns the meaning and dispatch of its
effect requests. Catalog owns registration. The review traces those seams;
it does not complete reviews of those components.

## Public contract

| Surface | Supported contract |
| --- | --- |
| Module authoring | `use Jido.Action` requires `name:` and `run/2`. It accepts `id:`, `vsn:`, `description:`, `schema:`, and `output_schema:`. Schemas are static Joi data. Invalid configuration and a missing `run/2` stop compilation. |
| Generated API | `name/0`, `description/0`, `schema/0`, `output_schema/0`, `authoring_contract/0`, `validate_params/1`, and `validate_output/1`. The authoring contract can raise if a schema has no JSON Schema form; validation can still work. |
| Custom Action | The executable boundary requires `run/2`, `validate_params/1`, and `validate_output/1`. A minimal custom Action need not use generated metadata. Exec checks its callback results. |
| Input | Optional `on_before_validate_params/1` runs before schema parsing. Joi applies defaults, coercion, transforms, refinements, and the declared unknown-key policy. Normal parsed root structs become maps. |
| Result | `{:ok, map_or_output}`, optionally with a proper effect list; `{:error, reason}`, optionally with discarded effects. `:continue` and `:handoff` have specific Invoke and Handoff roles. They are not general Action success forms. |
| Output | `Output.raw/1,2`, `stream/1,2`, `batch/1,2`, `opaque/1,2`, and `preserve/1,2` carry `kind`, `value`, and map `meta`. Stream checks do not consume the enumerable. Batch requires a proper list. Preserve applies the output schema and keeps root shape; the other kinds bypass that schema. |
| Inline host API | `use Jido.Action.Inline`, `setup!/1`, `parse_bound!/3`, `parse_callback!/3`, `compile!/3,4`, and `target!/2`. Parsed AST is a compile-time host value. Lookup returns an ordinary Action target after the owner compiles. |
| Internal support | `validate_params_for/2`, `validate_output_for/2`, Validation parse/schema functions, and Inline Parser/Compiler/Owner exports support generated code. They do not add runtime authoring forms. |

A direct call to an Action's `run/2` does not add validation or a task.
`Jido.Exec` supplies that boundary. Effect requests are ordered opaque terms.
Exec carries them and does not dispatch them. A failed run or output check
does not expose successful effects. Output metadata has no dispatch meaning.

## Coverage and usage

Each row includes a success trace and a reachable failure trace. All rows are
traced; there is no blocked source area.

| Responsibility | Source and consumer evidence | Result |
| --- | --- | --- |
| Module contract | `action.ex`; Instruction Compiler/Config; `action_test.exs`; missing-callback consumer variant | Generated metadata and valid schemas work. Missing `run/2`, unknown options, and non-static schemas fail. |
| Custom contract | `exec/validation.ex`, `exec/node/action.ex`; `exec/validation_contract_test.exs` | Minimal callbacks work. Invalid returns, exceptions, throws, and exits enter the Exec error boundary. |
| Input and output validation | `action/validation.ex`; `validation_test.exs`, `parse_contract_test.exs`; Flow input/output and Iterate callers | Schema policy, normalization, and preserved shape are distinct contracts. Invalid values and schema failures return structured errors. |
| Output and effects | `action/output.ex`; `output_test.exs`; Exec Action node; Flow boundary/effect tests; Agent Flow effects | All five kinds are traced. Invalid envelopes and improper effect lists fail. Effect order and failure behavior are checked at composition seams. |
| Inline parsing | `action/inline.ex`, `inline/parser.ex`; inline and host tests; Flow inline Steps and Agent callback authoring | Bound sources stay inert AST. Callback input, clauses, guards, context, and supported patterns work. Invalid bindings and options fail at a source location. |
| Inline compiler and owner | `inline/compiler.ex`, `inline/owner.ex`; Flow/Agent hosts; `inline_host_build_test.exs`; `test/consumers/inline_consumer` | Owner scope and private helpers survive. Typed identity, duplicate rejection, reservations, late hooks, and loaded target replacement are traced. Consumer compilation, recompilation, and release builds passed. |

The review also read the Action guides, inline-host guide, supported single
Action example, relevant Instruction/Joi/Codec records, and Action, Inline,
Validation, and Output obligations. Current callers use Validation from Exec
and Flow. Flow and Agent use the Inline host API. AI Actions use the normal
Action module contract. These consumers justify keeping a small generic Action
boundary instead of adding runtime or Agent rules to it.

## Findings

### F1 — Keep one inline reservation state value

- **Class:** Safe refinement. **Priority:** P3. **Confidence:** High.
- **Evidence:** `lib/jido/action/inline/owner.ex:40`, `:49`, and `:65`.
  `reserve_function!/3` stores each `{name, arity}` in both the
  `:__jido_inline_reserved_labels__` map and the `:__jido_inline_reserved__`
  list. The definition hook reads the list; error reporting reads the map.
  Each admitted reservation updates both. No other reader or writer was found
  in source, tests, or guides.
- **Consumer impact:** Current behavior is correct. Two private state values
  must stay consistent when host reservations change.
- **Smallest recommendation:** Use `Map.has_key?/2` on the label map in the
  definition hook. Remove the reservation list and its update. Keep labels,
  generated-function exceptions, default-argument arity checks, and errors.
  No shared owner abstraction is needed.
- **Compatibility:** Low risk for the supported host API. No public API or
  generated target identity needs to change.
- **Verification after a change:** Run reserved-function, default-argument,
  repeated-setup, and late-hook cases in the Inline and host tests. Run the
  isolated consumer build tests. This review did not apply the change.

## Decisions and behavior to preserve

| Decision | Evidence and reason | Reopen condition |
| --- | --- | --- |
| Preserve opaque effects | Action result contract, Exec effect tests, and Agent effect consumers need caller-owned request meaning. A new Action directive type would add a domain dependency. | A concrete caller needs a common request contract. |
| Preserve normal and explicit output boundaries | Validation and Output tests distinguish normalized maps from raw, stream, batch, opaque, and preserved values. Preserve must still apply its schema. | A deliberate public output contract change. |
| Defer any `raw`/`opaque` merge | Both share validation mechanics, but their `kind` tags are public data. Both appear in guides, the public API reference, and direct tests. No production discriminator was found. This is an API decision, not a safe deletion. | Decide whether callers still need both tags and set a migration rule. |
| Preserve custom-validator containment | A custom validator can change its result or replace an envelope. Generated validator behavior does not prove that a custom implementation is valid. | The public custom Action contract changes. |
| Preserve separate parse results | `parse/3` normalizes root structs; `parse_preserving_shape/3` serves preserved outputs and iterator validation. These are not duplicate APIs. | Their consumers no longer need distinct shapes. |
| Preserve inline owner callbacks and parsed AST fields | Lexical scope, attributes, private helpers, body clauses, and host source mapping have direct tests and consumers. Identity names a declaration, not deployed code. | A new authoring contract removes one of those requirements. |

The review found no safe public API removal. It rejected a shared Action/Flow
inline compiler: Action bodies retain owner scope; embedded Flow bodies use
generated-module scope and have different replacement guarantees. Similar hook
syntax alone does not justify a common framework.

## Checks and proof gaps

- The shared focused command passed **587 tests**, seed `0`. It included all
  `test/jido/action`, all `test/jido/flow`, Flow codec tests, Exec validation,
  Flow execution and effect-count tests, and Agent Flow effects/modes tests.
  This includes the isolated consumer build tests. The exact command is in
  the [Flow record](flow.md#r7-checks-and-proof-gaps).
- `mix test.authoring --warnings-as-errors` passed **8 tests**. This is a
  separate command total.
- `MIX_ENV=test mix compile --warnings-as-errors` passed.
- `mix format --check-formatted` passed.
- A separate read-only verifier checked both records against current source
  and contract evidence. It found no material record error. Local links,
  checklist counts, and patch checks passed. Test totals are coordinated
  evidence; the verifier did not rerun the tests.
- The first focused command could not acquire Mix's local TCP filesystem
  lock in the sandbox (`:eperm`). The retry with local TCP access passed.
- The full CI, quality gate, live calls, and runtime-version matrix were not
  run. These checks do not establish full release readiness or verify the
  separate R6 fixes in other components.
- Covenant still uses `jido_action.*` proof IDs. Action and Inline module
  lists include Instruction-owned support. Keep that proof alignment work
  separate from the confirmed Action boundary. Tagged tests are evidence;
  this review did not run the full `mix test.contracts` command.

The later Flow repair checks passed 593 focused Action/Flow boundary tests
and 8 public authoring tests. Their static gate stopped at unused Dialyzer
filters, including five for unchanged Action source. A separate test-environment
run reported three Action callback type mismatches. Their return terms and
source lines match the deliberate `UnsupportedResult`,
`ErrorWithExtrasAction`, and `KillingAction` failure fixtures. The filters need
alignment; these reports do not establish a new production Action defect.
The Action source and its filters were not changed by the Flow repair work.

Review completion does not adopt F1 or the deferred API decision. No Action
source or dependencies changed. The user's later Flow fix request is recorded
under [Flow R8](flow.md#r8--local-flow-repairs). No commit or push was made.

## Sources

- [Action](../../lib/jido/action.ex)
- [Validation](../../lib/jido/action/validation.ex)
- [Output](../../lib/jido/action/output.ex)
- [Inline API](../../lib/jido/action/inline.ex)
- [Inline compiler](../../lib/jido/action/inline/compiler.ex)
- [Inline parser](../../lib/jido/action/inline/parser.ex)
- [Inline owner](../../lib/jido/action/inline/owner.ex)
- [Action tests](../../test/jido/action)
- [Custom validator tests](../../test/jido/exec/validation_contract_test.exs)
- [Consumer builds](../../test/consumers/README.md)
- [Action obligations](../../test/contracts/jido_action/action.obligations.md)
- [Inline obligations](../../test/contracts/jido_action/inline.obligations.md)
- [Output obligations](../../test/contracts/jido_action/output.obligations.md)
- [Validation obligations](../../test/contracts/jido_action/validation.obligations.md)
