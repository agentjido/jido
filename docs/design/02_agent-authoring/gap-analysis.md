> Gap analysis. This document is pending approval.

# Agent authoring gap analysis

## Scope and owner

This report covers the Agent authoring seam in `jido`. It covers Agent module
authoring, the Spark DSL, inline Actions, direct map and keyword forms, Builder,
Agent and Plugin Codecs, validation, generated interfaces, and Agent authoring
extensions. Code under `lib` is the source of truth for implemented behavior.

The `jido` package owns the canonical `%Jido.Agent{}` definition and instance,
the Agent DSL, Builder, Codec, Registry, generated route interfaces, and the
extension-lowering host. `jido_action` owns Action, Flow, executable, and inline
Action contracts. `jido_signal` owns Signal construction and route
normalization. This report does not review those packages outside the calls
that the Agent authoring seam makes.

This report separates current facts from proposals. Text in
`authoring.md` under “Historical module-only proposal” is not implemented
behavior (`docs/design/02_agent-authoring/authoring.md:20-40`).

## Implemented baseline

Current facts:

- `Jido.Agent.new/1` builds a neutral definition. `instantiate/2` adds only an
  ID and state. `new/2` builds an instance from an Agent module
  (`lib/jido/agent.ex:259-307`). Definition validation rejects non-nil instance
  data and instance validation accepts only `:id` and `:state` as overrides
  (`lib/jido/agent/validation.ex:35-39`,
  `lib/jido/agent/validation.ex:186-205`,
  `lib/jido/agent/validation.ex:303-307`).
- `use Jido.Agent` installs Spark, inline Action support, module accessors,
  module constructors, `cmd/3`, and persistence callbacks
  (`lib/jido/agent.ex:137-247`).
- The Spark compiler combines keyword and block fields, lowers extensions,
  records interface metadata, generates helper functions, and schedules
  after-verification when a block, source, or extension is present
  (`lib/jido/agent/dsl/compiler.ex:7-71`).
- A route can use one named target or one inline Action. The inline body becomes
  a normal Action module. A route cannot contain both forms
  (`lib/jido/agent/dsl/macros.ex:27-71`,
  `lib/jido/agent/dsl/macros.ex:104-135`).
- A `define` entry generates tagged Signal, bang Signal, and live call helpers.
  The compiler checks route exactness, route uniqueness, source validity,
  argument order, field presence, and function conflicts
  (`lib/jido/agent/dsl/compiler.ex:145-229`,
  `lib/jido/agent/dsl/compiler.ex:236-278`). Runtime packaging separates input,
  Signal, context, and timeout options (`lib/jido/agent/interface.ex:8-71`).
- Builder records its first error, keeps route order, checks each appended
  target, and sends final output through `Agent.new/1` and `Agent.instantiate/2`
  (`lib/jido/agent/builder.ex:34-65`,
  `lib/jido/agent/builder.ex:80-126`).
- Agent Codec stores static definition data. Decode resolves modules, schemas,
  Plugins, executable targets, route matches, atoms, and static structs through
  a trusted Registry, then calls the canonical constructor
  (`lib/jido/agent/codec.ex:27-99`). Plugin Codec uses the same Registry and
  excludes Plugin state and runtime (`lib/jido/plugin/codec.ex:1-46`).
- Codec data uses closed tagged records and checks document depth, node,
  collection, and string limits (`lib/jido/agent/codec/data.ex:6-59`,
  `lib/jido/agent/codec/data.ex:61-170`). Registry aliases point directly to a
  canonical entry (`lib/jido/agent/codec/registry.ex:27-40`,
  `lib/jido/agent/codec/registry.ex:127-145`).
- Agent extensions lower DSL entities to normal Agent configuration. Final
  configuration still goes through common validation
  (`lib/jido/agent/extension.ex:1-20`,
  `lib/jido/agent/extension.ex:57-95`).

## Aligned contracts

Current facts:

- The design correctly states the definition and instance split. The public
  module documentation states the same split (`docs/design/02_agent-authoring/dsl-and-interfaces.md:198-212`,
  `lib/jido/agent.ex:3-10`).
- Map, keyword, module, Spark, Builder, and JSON paths can produce the same
  canonical Agent for the covered fixture. The parity test checks definition,
  instance, Plugin order, route order, and Codec exclusion of ID and state
  (`test/jido/agent/authoring_test.exs:207-235`).
- Inline route Actions are compiled executable modules. Builder and Codec can
  reuse the compiled target returned by `route_action/1`
  (`lib/jido/agent.ex:215-219`,
  `test/jido/agent/authoring_test.exs:257-284`).
- Route helpers preserve omitted optional input and explicit `nil`, `false`,
  and zero. They keep Signal options separate from live-call options
  (`lib/jido/agent/interface.ex:29-71`,
  `test/jido/agent/authoring_test.exs:320-333`,
  `test/jido/agent/authoring_test.exs:413-450`).
- Generated helper documentation and types describe the generated arities and
  broad raw input contract (`lib/jido/agent/dsl/generator.ex:22-29`,
  `lib/jido/agent/dsl/generator.ex:81-129`,
  `test/jido/agent/authoring_test.exs:335-388`).
- Direct route maps, route tuples, Builder routes, DSL routes, and Codec route
  records use `defaults`, not Agent route `params`
  (`lib/jido/agent/authoring.ex:43-79`,
  `test/jido/agent/authoring_test.exs:595-640`,
  `test/jido/agent/authoring_test.exs:731-742`).
- The Codec does not derive atoms or modules from stored strings. It also
  rejects unknown fields, invalid tags, duplicate decoded keys, runtime values,
  and oversized documents (`lib/jido/agent/codec.ex:72-99`,
  `test/jido/agent/authoring_test.exs:529-593`).
- The Builder first-error and declaration-order claims have direct tests
  (`test/jido/agent/builder_test.exs:19-80`). Extension ordering, unclaimed
  entities, target ownership, and common validation also have direct tests
  (`test/jido/agent/authoring_extension_test.exs:111-286`).

## Gaps

### Missing implementation

Current facts:

1. **There is no definition revision contract.** The Agent schema and accepted
   definition keys have no `definition_revision` field
   (`lib/jido/agent.ex:96-123`, `lib/jido/agent/validation.ex:10-20`). The Codec
   document has no revision field (`lib/jido/agent/codec.ex:27-28`,
   `lib/jido/agent/codec.ex:56-66`). A checkpoint saves the full definition but
   no explicit definition revision (`lib/jido/agent.ex:402-412`). Module restore
   uses the current module definition and does not compare it with the saved
   static definition (`lib/jido/agent.ex:565-574`). The authoring design already
   marks versioned-module work as separate work
   (`docs/design/02_agent-authoring/authoring.md:11-18`). The enabled research
   probe has a skipped revision-mismatch assertion
   (`test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:22-27`).

2. **Extension lowering has only a compile-time DSL host.** The compiler calls
   `Jido.Agent.Extension.lower/3` (`lib/jido/agent/dsl/compiler.ex:47-52`).
   Builder has no extension field or lowering call
   (`lib/jido/agent/builder.ex:34-65`, `lib/jido/agent/builder.ex:110-126`). Agent
   Codec also has no extension record or lowering call
   (`lib/jido/agent/codec.ex:27-28`, `lib/jido/agent/codec.ex:72-99`). Therefore,
   the guidance to keep semantic lowering usable from data authoring is not an
   implemented common entry point (`lib/jido/agent/extension.ex:14-16`).

3. **The common validator does not enforce portable route predicates.** Direct
   and Builder routes accept any unary function because common route
   normalization accepts it and `validate_routes/1` checks only executable
   targets (`lib/jido/agent/validation.ex:269-293`). Registry accepts a route
   match only when it is an external unary capture
   (`lib/jido/agent/codec/registry.ex:101-105`). An Agent can therefore be valid
   in direct or Builder form but not encodable through Agent Codec.

### Design/code conflict

Current facts:

1. **`__agent_config__/0` is not always canonical normalized Agent data.** The
   compiler fills defaults and stores the result directly
   (`lib/jido/agent/dsl/compiler.ex:35-65`). Canonical validation happens later
   when `agent/0` calls `__definition_from_module__/2`
   (`lib/jido/agent.ex:182-188`). Keyword-only Plugin and route declarations can
   therefore remain in input form inside `__agent_config__/0`. The statement
   that the compiler stores normalized declarations is too strong
   (`docs/design/02_agent-authoring/dsl-and-interfaces.md:101-104`). The
   canonical public value is `agent/0`, not `__agent_config__/0`.

2. **The “external unary match” rule is not common to all authoring forms.** The
   design presents this as a route rule
   (`docs/design/02_agent-authoring/dsl-and-interfaces.md:51-55`). The common
   validator accepts local closures, but Codec Registry rejects them, as shown
   by the code references in missing implementation item 3.

3. **Route default syntax has a compatibility exception that the design does
   not state.** Explicit `defaults:` requires a plain map
   (`lib/jido/agent/authoring.ex:43-47`, `lib/jido/agent/authoring.ex:107-110`).
   A legacy `{target, defaults}` tuple accepts any map, including a struct
   (`lib/jido/agent/authoring.ex:28-31`). Tests preserve this difference and
   preserve struct defaults through Codec
   (`test/jido/agent/authoring_contract_test.exs:34-56`,
   `test/jido/agent/codec_test.exs:29-50`). The design says the forms use the
   same `defaults` option but does not record this exception
   (`docs/design/02_agent-authoring/dsl-and-interfaces.md:97-99`).

4. **The inline Action dependency version is stale.** The design names
   `jido_action` 3.0.0-beta.6
   (`docs/design/02_agent-authoring/dsl-and-interfaces.md:58-67`). This repository
   uses the sibling `jido_action` path dependency (`mix.exs:351-359`), and that
   sibling declares version 3.0.0-beta.8 (`../jido_action/mix.exs:4`).

5. **The verification counts and locations are stale.** The design says the
   five Basic fixtures retain 15 tests and adds five fixture parity tests
   (`docs/design/02_agent-authoring/dsl-and-interfaces.md:263-270`). The Basic
   index lists 16 tests (`test/examples/01_basic/README.md:1-18`), and the suite
   contains 16 test declarations. The cross-form parity proof is one focused
   test in `authoring_test.exs`, not five Basic fixture parity tests
   (`test/jido/agent/authoring_test.exs:207-255`).

6. **The historical downstream example names the wrong boundary.** It uses
   `Jido.Agent` as both the core module and an alleged downstream abstraction,
   then says that `Jido.Agent` is outside core
   (`docs/design/02_agent-authoring/authoring.md:170-186`). In implemented code,
   `Jido.Agent` is the core Agent value and macro (`lib/jido/agent.ex:1-3`,
   `lib/jido/agent.ex:137-145`). The section is historical, but this name still
   makes its ownership statement incorrect.

### Missing decision

Current facts:

1. **Interface parity has no explicit boundary decision.** A `define` entry and
   `signal_source` create compile-time module functions and private interface
   metadata (`lib/jido/agent/dsl/compiler.ex:54-67`). Interface metadata does not
   enter `%Jido.Agent{}`, Builder, or Codec. The design correctly says that the
   metadata is not part of an Agent or checkpoint
   (`docs/design/02_agent-authoring/dsl-and-interfaces.md:101-104`), but it also
   says all authoring forms are equal (`docs/design/02_agent-authoring/dsl-and-interfaces.md:198-212`).
   It does not decide whether equality covers only the canonical Agent value or
   also the module interface.

2. **Extension parity has no explicit boundary decision.** Current extension
   syntax is Spark-only, while the extension documentation asks lowerers to be
   usable from data authoring (`lib/jido/agent/extension.ex:14-16`). The design
   must decide whether Builder and Codec author only the lowered result or
   whether they also carry extension declarations.

3. **The stable definition authority is not decided for current V3.** Direct
   maps and Codec documents can name any valid Agent behavior module, and
   neutral definitions can exist without an authoring module. The deferred
   module-only proposal instead requires one versioned module authority
   (`docs/design/02_agent-authoring/authoring.md:42-91`). The current design
   needs one explicit choice before revision and restore rules can be complete.

4. **Codec behavior for complete instances needs a stated rule.** Public
   examples pass an Agent instance to `Codec.encode/1`, although the document
   stores only static data (`lib/jido/agent/codec.ex:3-17`). Encoding validates
   the complete instance and can parse state more than once
   (`lib/jido/agent/codec.ex:29-46`). A focused test records failure for a
   non-idempotent state transform (`test/jido/agent/authoring_test.exs:513-527`).
   The design must decide whether encode accepts instances, ignores their state
   by first taking `Agent.definition/1`, or requires neutral definitions only.

### Missing verification

Current facts:

- There is no active passing test for definition revision mismatch. The only
  direct acceptance assertion is skipped, as cited above.
- There is no cross-form test for a route match that direct and Builder forms
  accept but Codec Registry cannot carry. Current route Codec coverage uses an
  external capture (`test/jido/agent/authoring_test.exs:66-87`,
  `test/jido/agent/authoring_test.exs:453-472`).
- There is no Builder or Codec parity test for extension declarations because
  those forms have no extension-lowering entry point. Extension tests cover the
  Spark host (`test/jido/agent/authoring_extension_test.exs:111-286`).
- The parity test uses one Agent fixture. It does not rebuild each of the five
  Basic fixtures through map, keyword, Builder, and JSON forms
  (`test/jido/agent/authoring_test.exs:207-255`).
- There is no focused assertion that `__agent_config__/0` is canonical for a
  keyword-only declaration. Current parity starts from that private value and
  sends it through `Agent.new!/1`, which performs the missing normalization
  (`test/jido/agent/authoring_test.exs:207-218`).
- Many public Builder and Codec functions have documentation but no type
  specification. Examples include Builder setters and bang builders
  (`lib/jido/agent/builder.ex:67-80`, `lib/jido/agent/builder.ex:123-126`) and
  Agent Codec encode and decode functions (`lib/jido/agent/codec.ex:29-39`,
  `lib/jido/agent/codec.ex:72-99`). Generated helpers do have exact specs. The
  public authoring surface does not have the same static interface coverage.

Verification run for this report on 2026-09-08:

- Focused Agent authoring, Builder, Codec, Registry, validation, and extension
  suites: 64 tests passed.
- Basic example suite with the `example` tag included: 16 tests passed.

These passing runs prove the current tested behavior. They do not prove the
missing contracts above.

## Narrow dependency notes

Current facts:

- `jido_action` supplies `Jido.Action.Inline`, executable resolution and
  validation, and Flow schemas. Agent route compilation delegates inline Action
  parsing and compilation to it (`lib/jido/agent/dsl/macros.ex:4-5`,
  `lib/jido/agent/dsl/macros.ex:50-62`). Agent definition validation delegates
  target validity to `Jido.Executable` (`lib/jido/agent/validation.ex:282-293`).
  A change to inline callback grammar or executable descriptors needs a
  coordinated `jido_action` compatibility test.
- `jido_signal` supplies `Jido.Signal.new/3` and `Jido.Signal.Router.normalize/1`.
  Agent interface packaging calls the Signal constructor
  (`lib/jido/agent/interface.ex:63-70`), and all route forms pass through Router
  normalization (`lib/jido/agent/authoring.ex:43-79`). Predicate portability
  must be fixed at one clear owner. If `jido_signal` continues to permit runtime
  closures, `jido` must apply the stricter authoring or Codec rule itself.
- Plugin Codec is adjacent but remains in `jido`. It shares Agent Registry and
  data records, so any Agent Codec version change must keep Plugin record
  compatibility explicit (`lib/jido/plugin/codec.ex:1-8`).

## Ordered recommendations

The following items are proposals, not current behavior:

1. Decide the definition authority and revision contract first. If module-owned
   revisions are required, add a positive revision to the canonical definition,
   module DSL, Codec, checkpoint, and restore comparison. Enable the existing
   revision-mismatch acceptance test.
2. Make route predicate portability one common rule. Prefer external unary
   captures for authoring data that must pass through Codec. Enforce that rule
   in common Agent validation, or state clearly that runtime closures make an
   Agent non-encodable. Add a cross-form test.
3. Define “equal authoring forms” as equality of canonical Agent definitions.
   State separately that generated interfaces are compile-time module API. Then
   decide whether extensions must expose a public data lowerer or whether
   Builder and Codec accept only already-lowered configuration.
4. Normalize the public meaning of `__agent_config__/0`. Either store canonical
   normalized configuration or document it as private compiler input and use
   `agent/0` as the only canonical value.
5. Decide whether Agent Codec accepts complete instances. If it does, encode
   `Agent.definition(agent)` without parsing live state. If it does not, reject
   instances with a direct error and update examples.
6. Document or remove the struct-default compatibility exception. Keep one
   clear rule for explicit `defaults:` and `{target, defaults}` forms.
7. Correct the dependency version, verification counts, parity-test statement,
   and historical downstream module name. Add public types for Builder and
   Codec functions as part of the same documentation pass.

## Evidence reference map

The main implementation evidence is in:

- `lib/jido/agent.ex:48-84`, `lib/jido/agent.ex:137-247`, and
  `lib/jido/agent.ex:259-320` for the public authoring surface;
- `lib/jido/agent/validation.ex:10-20` and
  `lib/jido/agent/validation.ex:131-205` for canonical construction;
- `lib/jido/agent/dsl/compiler.ex:7-71` and
  `lib/jido/agent/dsl/compiler.ex:145-278` for DSL and interfaces;
- `lib/jido/agent/dsl/macros.ex:27-71` for inline route Actions;
- `lib/jido/agent/builder.ex:34-126` for Builder;
- `lib/jido/agent/codec.ex:27-99`, `lib/jido/agent/codec/data.ex:112-170`, and
  `lib/jido/agent/codec/registry.ex:27-145` for Codec and Registry;
- `lib/jido/agent/extension.ex:57-95` for extension lowering;
- `test/jido/agent/authoring_test.exs:207-284` and
  `test/jido/agent/authoring_test.exs:320-745` for authoring verification; and
- `test/jido/agent/authoring_extension_test.exs:111-286` for extension
  verification.
