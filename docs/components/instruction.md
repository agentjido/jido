---
title: Jido.Instruction component
status: current
last-reviewed: 2026-11-10
---

# Jido.Instruction component

Purpose: Record the invocation value, shared compiler, and configuration review.
Review result: All four review checks are complete (R5). Findings remain open.
No recommendation in this record is approved for implementation.

## Public contract

| Surface | Operations and behavior |
| --- | --- |
| Construction | `new/1`, `new!/1` accept an atom-keyed map or keyword list with `target`, optional `kind`, `params`, `context`, and `metadata`. Return `{:ok, instruction}` or `{:error, exception}`; the bang form raises. |
| Resolution | `resolve/1,2,3` accepts an Action module, Flow module, runtime Flow, or nested Instruction. It returns a resolved value with current kind and exact target. |
| Deferred module binding | `template/2,3` returns an inert module reference with declared kind and empty params/context. Invalid construction raises `ArgumentError`. `bind/3,4` returns a checked Instruction or structured error. |
| Contract check | `validate/1` refreshes target classification and checks executable callbacks. It returns `:ok` or `{:error, exception}` without executing work. |
| Internal exports | `normalize!/1,2,3`, `validate_resolved/1`, `validate_template/1`, `target_kind/1`. Compiler and Config exports support Action and Flow authoring. |

Construction and resolution normalize nil and keyword call data to maps.
Nested merges are shallow; outer keys replace inner keys. Call-site params
and context replace stored keys. Metadata has no execution-policy meaning.
Removed `id`, `action`, `flow`, and `opts` keys return errors.

Classification checks the current compiled module on each resolution. Action
and Flow behaviors select the kind; generated Flows use the shared Action
behavior plus their declared codec kind. A module that declares both behaviors
is rejected. Action validation requires `run/2`; Flow requires `flow/0`.
Both require `validate_params/1` and `validate_output/1`. Runtime Flow values
are accepted without those module checks. Resolution alone does not validate
all callbacks. Exec and Agent routes explicitly do that next.

Bind accepts raw non-map params until Action validation. Resolve and new
accept map-shaped params only. Therefore, a raw bound value is not guaranteed
to pass through resolve again. Constructor maps are not a JSON or stored format.

## Compiler and Config boundary

All three files (995 lines) are in Reach `definitions`. Compiler generates
name, description, schemas, validation delegates, authoring contract, codec
kind, and Catalog manifest functions for Action and Flow modules. It captures
JSON Schema errors without disabling execution and raises them when the
authoring contract is requested. Config validates names, static schemas,
options, duplicate DSL declarations, IDs, and versions. It supplies located
compile errors and runtime Flow errors. Neither module owns Action execution.

Compiler exports `__using__/1`, `compile_contract/2`, and `contract!/1`.
Config exports `validate_options!/4,5`, `allow_options!/4,5`,
`compile_error!/2`, `validate_name/1,2`, `validate_config_schema/1,2`,
`validate_map_schema/1,2`, `validate_static_data/1`, `prepare!/3`,
`validate_flow/1`, `flow_name/1`, `description/1`, and `schema/2`.
These are internal support functions, not new user authoring entry points.

## Usage, duplication, and Elixir design

Exec.run/4, Exec.compile, Invoke, Flow validation/defaults, Agent Route and
Turn, AgentServer lifecycle, AI tool selection, and snapshot upgrades use
resolution or target checks. Action, Flow module compilation, and inline
Action compilation use Compiler and Config. Flow DSL parsing uses the same
Config checks. This sharing removes repeated Action/Flow metadata code.

- **F1 — Design decision, P3, high confidence:** No production call to `normalize!/3`,
  `template/3`, or `bind/4` was found in `lib/`. They have substantial direct
  tests and public contract obligations. The source says canonical Flow uses
  small call records. Consider removing the hidden raising helper first.
  Decide whether deferred templates have a supported external use before
  removing them. Tests alone do not establish product need.
- **F2 — Design decision, P2, high confidence:** Template metadata is described as portable, but only
  `is_map` is checked. A PID inside metadata is accepted. Either enforce Term
  validation for inert metadata or narrow the documentation claim.
- **F3 — Design decision, P3, high confidence:** New rejects selected removed fields but silently
  ignores other unknown keys. This can hide a misspelled field. A closed
  constructor would be clearer, but needs an explicit compatibility decision.
- Keep runtime context out of portable Flow call records. Keep current-module
  classification at execution boundaries. Do not add a target-kind cache that
  can survive reload with stale data.
- Compiler depends on Action validation and Config depends on Catalog identity
  rules. These are current same/lower-layer dependencies. Splitting Compiler
  into a second generic DSL would add an abstraction without a new contract.

## Coverage

Source state: HEAD `85023dd` with local changes. Primary review and a second
read-only reviewer checked each row.

| Responsibility | Traces | Result |
| --- | --- | --- |
| Invocation value | Constructors, templates, bind, nested merge, callback checks, stale kinds and raw params | Source, callers and focused tests checked. |
| Compiler | Action/Flow metadata, schemas, validation delegates, codec/manifest generation | Authoring, inline consumers, and failure tests checked. Broad CI has a build-test limit. |
| Config | Options, names, schema/static data, Flow errors and compile locations | Source and Action/Flow callers checked. |
| Runic protocols | Action node conversion, Flow compilation, identity document | `lib/jido/exec/runic/instruction.ex` traced. Identity is not a portable decoder. |

## Evidence, checks, and proof gaps

Reviewed all three source files, Exec/Agent/Flow callers, both Instruction test
files, and `jido_action.instruction.I2` through `I6`. The first focused R5 run
passed 184 tests, including Instruction. Tests cover raw binding, stale kinds,
reload, callback omissions, nested overrides, removed fields, and errors.

Compiler and Config proof is under `jido_action.action` and inline/authoring
contracts, not the Instruction module list. Current ownership records need
alignment before a future public API cut. No production-call evidence was
found for the deferred template lifecycle. This is a recommendation, not proof
that an external user cannot depend on it.

## Sources

- [Instruction](../../lib/jido/instruction.ex)
- [Compiler](../../lib/jido/instruction/compiler.ex)
- [Config](../../lib/jido/instruction/config.ex)
- [Exec runtime](../../lib/jido/exec/runtime.ex)
- [Flow validation](../../lib/jido/flow/validation.ex)
- [Instruction tests](../../test/jido/instruction/instruction_test.exs)
- [Target tests](../../test/jido/instruction/target_test.exs)
- [Instruction obligations](../../test/contracts/jido_action/instruction.obligations.md)
- [Action obligations](../../test/contracts/jido_action/action.obligations.md)
- [Reach layers](../../.reach.exs)
