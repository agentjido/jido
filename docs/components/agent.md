---
title: Jido.Agent component
status: current
last-reviewed: 2026-11-19
---

# Jido.Agent component

Jido.Agent owns fixed Agent definitions, immutable instance values, and
the evaluation of one Signal into a complete candidate and ordered
Directives. This review completed all four checks in
[components.md](../../components.md) for [tracker #453](https://github.com/agentjido/jido/issues/453).
The source was [`release/v3` at `6fdc009a`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5).

## Public surface

| Entry point | Contract |
| --- | --- |
| `define/1`, `define!/1` | Normalize and validate a Map definition with nil `id` and `state`. A definition holds the schema, static initial state, metadata, source, routes, topology, and Plugin declarations. The bang form raises the validation error. |
| `definition/1`, `definition?/1`, `instance?/1` | Project the neutral definition from an Agent value or resolve a compiled module. The predicates check shape. |
| `instantiate/2`, `instantiate!/2` | Accept a definition or module and Map or keyword options. Require a nonempty `:id` and accept an optional plain Map as `:state`. Explicit fields replace declared initial fields. Run the optional `initialize/2` callback before Joi adds defaults. |
| `validate/1`, `schema/1` | Validate canonical definition data or a complete instance. Return the state schema with Plugin-owned fields through `schema/1`. Stored-state checks preserve supplied values and reject missing required fields, unknown fields, and conversion. |
| `set/2` | Replace supplied top-level domain fields and validate the complete state. Preserve identity, definition, omitted fields, and Plugin-owned fields. A supplied nested Map replaces the previous Map. |
| `cmd/3` | Accept a Signal and keyword options. Reserve Jido's context keys. For executable routes, normalize Map, keyword, or nil input and give it precedence over route defaults. Return `{:ok, candidate, directives}`, `{:handoff, candidate, instruction, directives}`, or `{:error, reason}`. |
| `build_signal/3` | Build a causally linked Signal with the Agent source from the Action context. |
| `use Jido.Agent` | Compile state, ordered routes, topology, and Plugin contributions into the canonical value. Generate `definition/0`, `schema/0`, `vsn/0`, constructors, the command delegate, `route_executable!/1`, and named Signal helpers for exact routes. |

An Agent can supply optional `checkpoint/2` and `restore/2` callbacks
for a custom portable payload. Persistence calls them. Route and Directive
values specify handler selection, state and reply projection, and effect
requests. Topology holds static members and connections. Address identifies an
Agent across activations. View projects a bounded summary. Codec uses trusted
Catalog references for Agent documents. Runner, validation, schema
implementation, and Plugin preparation support the same Agent contract.

[Facade](../../lib/jido/agent.ex) ·
[DSL](../../lib/jido/agent/dsl.ex) ·
[Agent obligations](../../test/contracts/jido/agent.obligations.md)

## API contract usage and evidence

- [Agent authoring equivalence](../../test/authoring/agent_equivalence_test.exs)
  checks the DSL, Map, and Codec paths.
  [DSL contract tests](../../test/jido/agent/dsl_authoring_contract_test.exs)
  cover generated helpers and route target lookup. The generated
  `cmd/3` delegates to the facade. At the review commit, its result spec
  omitted Handoff.
- [State tests](../../test/jido/agent/state_test.exs) and
  [replacement tests](../../test/jido/agent/replacement_test.exs) cover initialization
  order, closed stored state, and shallow replacement. The
  [candidate completeness tests](../../test/jido/agent/candidate_completeness_test.exs)
  and [state boundary tests](../../test/jido/agent/state_boundary_test.exs)
  show that direct and live evaluation reject an invalid candidate.
  [Persistence Snapshot](../../lib/jido/persistence/snapshot.ex) validates
  the instance again at the storage boundary.
- [Route selection tests](../../test/jido/agent/selection_test.exs) cover
  declaration order, route defaults, and direct and live input parity. First
  match is the default. An admitted Agent Plugin route selector can select
  another matching declaration. [Evaluation tests](../../test/jido/agent/evaluation/contract_test.exs)
  cover reserved context, Plugin inputs, Directive order, Handoff, and
  closed errors. At the review commit, the Handoff preparation case used
  Map parameters.
- [AgentServer Worker](../../lib/jido/agent_server/worker.ex#L2470) and
  [Lifecycle](../../lib/jido/agent_server/lifecycle.ex#L472) use the Agent
  Runner for admitted Turns and recovery. The AgentServer supplies runtime
  Plugin input after pure preparation. The Runner selects and binds the
  executable, projects the result, checks Directive and state ownership,
  applies Plugin reduction, and validates the complete candidate.
- [Agent View tests](../../test/jido/agent/view_contract_test.exs),
  [serialization tests](../../test/jido/agent/serialization_contract_test.exs),
  and [topology tests](../../test/jido/agent/topology_contract_test.exs)
  cover the value interfaces used by Catalog, Codec, and live topology.
  A repository search found no production references to the retired
  `Jido.Agent.Turn`, `Diff`, or `Mutation` types.

## Code quality

- **P3, repeated compiled definition validation.** A provider verification
  probe counted one call for generated `definition/0` and value-based
  instantiation. It counted two for `Agent.definition(module)` and generated
  module instantiation. Consolidate the checks within one call. Preserve
  canonical definitions, current target checks after code reload, topology
  cycle checks, and DSL diagnostics. Verify callback counts and authoring
  equivalence. [Module resolution](../../lib/jido/agent/validation.ex#L294) ·
  [DSL verification](../../lib/jido/agent/dsl.ex#L174) ·
  [#488](https://github.com/agentjido/jido/issues/488)
- **P3, repeated Runner steps.** Share admitted preparation, Plugin reduction,
  and the final complete-state replacement rule. Preserve each result
  shape and state and reply projection. Preserve error precedence and
  stages, Plugin and Directive order, and `set/2` ownership checks.
  Exercise normal completion, Handoff, and invalid candidates.
  [Runner](../../lib/jido/agent/runner.ex#L64) ·
  [State transition](../../lib/jido/agent/validation.ex#L245) ·
  [#489](https://github.com/agentjido/jido/issues/489)

## Elixir and OTP design

Keep one Agent component and one immutable Agent value. A definition and an
instance have distinct shapes, and their explicit constructors and validators
enforce the distinction at entry. The normal evaluation path keeps the Agent
identity and definition while it replaces or retains the complete state.
Keep Action routes as one-step Flows so all handler kinds use the same
execution boundary.

AgentServer owns OTP supervision and serialization of Turns. It supplies
admission, persistence, waits, cancellation, effect execution, and Handoff
coordination. The Agent Runner owns the candidate and Directive checks that
both hosts use. Direct evaluation returns a value and can run application code.
The live commit and effects stay with AgentServer. The Jido Instance owns
activation by Address and whole-definition upgrades. This pass inspected the
interfaces of Route, Directive, topology, Codec, View, Plugin, and AgentServer
for their effect on Agent. Their independent behavior has its own review scope.

[Agent Runner](../../lib/jido/agent/runner.ex) ·
[Live settlement](../../lib/jido/agent_server/worker.ex#L3122) ·
[AgentServer Handoff setup and restore](../../lib/jido/agent_server/lifecycle.ex#L488)

## Defects at the review commit

| Severity and issue | Evidence and impact | Acceptance |
| --- | --- | --- |
| P2 [#482](https://github.com/agentjido/jido/issues/482) | A terminal Handoff returned an Instruction with raw bound input. `Exec.run/1` on the Instruction succeeded. The live Turn failed at successor preparation after the predecessor committed. The Runner passes the raw value as caller parameters. [Runner preparation](../../lib/jido/agent/runner.ex#L124) | Preserve the bound data in live and restored successors. Verify the source Signal, protected context, state projection, map inputs, and early validation. |
| P2 [#483](https://github.com/agentjido/jido/issues/483) | A raising or malformed provider `verify/2` raised through Map authoring, value construction and validation, `set/2`, and direct `cmd/3`. Module instantiation returned a structured error for the same fault. [Definition validation](../../lib/jido/agent/validation.ex#L35) | Return structured errors with provider, callback, and path. Preserve successful results, explicit error details, and compilation locations. |
| P3 [#484](https://github.com/agentjido/jido/issues/484) | Map and DSL accepted `"not a URI"` as an Agent source. The generated helper and route reply failed when they built Signals. [Source validation](../../lib/jido/agent/validation.ex#L383) | Reject invalid sources at authoring. Preserve valid relative and absolute references and the optional source rule. |
| P3 [#486](https://github.com/agentjido/jido/issues/486) | A generated command returned a Handoff in the probe. The generated typespec covers success and error only. The prior R10 review also recorded this gap. [Generated command](../../lib/jido/agent/dsl.ex#L94) | Share the result type across the public and generated commands. Preserve all tuple shapes and the process-free evaluation boundary. |

## Review fixes

- Admitted Handoff preparation keeps the bound Instruction. Live execution
  checks its input early and gives the Flow its original bound value. Tests
  cover a string input in a live Turn and after durable activation.
  [#482](https://github.com/agentjido/jido/issues/482)
- Agent authoring reports structured provider callback errors. The tests
  check the errors from public tuple APIs and the cause and source location
  in compiler diagnostics. [#483](https://github.com/agentjido/jido/issues/483)
- Map, DSL, and Codec authoring apply the Signal URI-reference rule to an
  explicit source. Public and generated commands use `command_result()`.
  [#484](https://github.com/agentjido/jido/issues/484) ·
  [#486](https://github.com/agentjido/jido/issues/486)
- Module resolution and DSL verification validate the definition once per
  call. The Runner shares admitted preparation and complete candidate
  validation across both completion paths.
  [#488](https://github.com/agentjido/jido/issues/488) ·
  [#489](https://github.com/agentjido/jido/issues/489)

## Checks at the review commit

- `mix test test/jido/agent test/authoring` passed 294 Agent tests and excluded
  the eight tests with the authoring tag.
- `mix test.authoring` passed all eight authoring tests.
- `mix test.contracts` passed 2,924 tests with 112 exclusions and covered
  all 244 active obligations. This includes 22 Agent obligations and 10
  Agent evaluation obligations.
- `mix format --check-formatted` passed.
- Local probes confirmed the Handoff, provider callback, Signal source, and
  command typespec findings and counted repeated provider verification.
  The Handoff probe used one resident server.

The prior R10 review at `390d1c0f` established the immutable-definition
boundary. It recorded 3,192 package tests with 111 normal exclusions,
246 examples, and 321 active Covenant obligations. This review's source and
test results are the checks above.
